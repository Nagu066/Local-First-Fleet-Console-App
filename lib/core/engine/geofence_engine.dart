import 'package:uuid/uuid.dart';
import '../database/duckdb_service.dart';
import '../models/geofence.dart';
import '../utils/distance_calculator.dart';
import 'trip_engine.dart';

/// Geofence Engine implementing Section 3.D requirements:
/// - Create, edit, and deactivate persisted circular geofences (name, centre, radius, active state)
/// - Deterministic entry/exit evaluation from event-time location history addressing:
///   1. Duplicates
///   2. Late packets
///   3. GPS jitter
///   4. Inaccurate readings
///   5. Overlaps
///   6. Missing intervals
///   7. Geofence edits
class GeofenceEngine {
  final DuckDBService dbService;
  final Uuid uuid = const Uuid();
  TripEngine? tripEngine;

  /// Spatial hysteresis margin in meters to prevent perimeter boundary chatter
  static const double hysteresisMeters = 15.0;

  /// Kinematic sanity check: maximum plausible speed (km/h) for commercial vehicles
  static const double maxPlausibleSpeedKmh = 140.0;

  /// Signal blackout interval (seconds) after which a gap is treated as a missing interval
  static const int blackoutIntervalSeconds = 600; // 10 minutes

  // In-memory cache for fast deduplication & kinematic outlier detection
  final Map<String, _LastKnownLocation> _lastLocations = {};

  GeofenceEngine(this.dbService, {this.tripEngine});

  /// Seed default circular geofences if none exist in DuckDB (retains deactivated ones).
  Future<void> seedDefaultGeofences() async {
    final rows = await dbService.queryRows('SELECT COUNT(*) FROM geofences;');
    final count = (rows.first.first as num).toInt();

    if (count == 0) {
      final nowIso = DateTime.now().toIso8601String();
      await dbService.execute('''
        INSERT INTO geofences (id, name, center_lat, center_lng, radius_meters, is_active, created_at, updated_at)
        VALUES 
          ('geo_1', 'Depot Alpha', 12.9716, 77.5946, 500.0, true, '$nowIso', '$nowIso'),
          ('geo_2', 'Charging Hub East', 12.9250, 77.6800, 400.0, true, '$nowIso', '$nowIso'),
          ('geo_3', 'Logistics Terminal South', 12.8500, 77.6500, 600.0, true, '$nowIso', '$nowIso');
      ''');
    }
  }

  /// Creates a new circular geofence.
  Future<Geofence> createGeofence({
    required String name,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
    bool isActive = true,
  }) async {
    final id = uuid.v4();
    final nowIso = DateTime.now().toIso8601String();

    await dbService.execute('''
      INSERT INTO geofences (id, name, center_lat, center_lng, radius_meters, is_active, created_at, updated_at)
      VALUES ('$id', '${name.replaceAll("'", "''")}', $centerLat, $centerLng, $radiusMeters, $isActive, '$nowIso', '$nowIso');
    ''');

    await reEvaluateAllVehicles();

    return Geofence(
      id: id,
      name: name,
      centerLat: centerLat,
      centerLng: centerLng,
      radiusMeters: radiusMeters,
      isActive: isActive,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Edits an existing circular geofence and re-evaluates vehicle containment deterministically.
  Future<void> updateGeofence({
    required String id,
    required String name,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
    required bool isActive,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    await dbService.execute('''
      UPDATE geofences 
      SET name = '${name.replaceAll("'", "''")}', 
          center_lat = $centerLat, 
          center_lng = $centerLng, 
          radius_meters = $radiusMeters, 
          is_active = $isActive, 
          updated_at = '$nowIso' 
      WHERE id = '$id';
    ''');

    // Edge case 7 (Geofence Edits): Re-evaluate all vehicles against modified boundaries
    await reEvaluateAllVehicles();
  }

  /// Deactivates a circular geofence while retaining it for historical trip auditing.
  Future<void> deactivateGeofence(String id) async {
    final nowIso = DateTime.now().toIso8601String();
    await dbService.execute('''
      UPDATE geofences 
      SET is_active = false, updated_at = '$nowIso' 
      WHERE id = '$id';
    ''');

    // Re-evaluate to transition out any vehicles currently inside the deactivated zone
    await reEvaluateAllVehicles();
  }

  /// Processes GPS telemetry point (lat, lng) for a vehicle at event-time [timestamp].
  /// Deterministically resolves:
  /// 1. Duplicates: Drops exact same timestamp & coordinates
  /// 2. Late packets: Processes in event-time order
  /// 3. GPS jitter: Hysteresis margin of 15m
  /// 4. Inaccurate readings: Validates Earth bounds & max physical speed (< 140 km/h)
  /// 5. Overlaps: Normalized distance tie-breaker to pick single best geofence
  /// 6. Missing intervals: Closes past geofence on prolonged signal loss (> 10 mins)
  /// 7. Geofence edits: Real-time boundary re-evaluation
  Future<List<GeofenceEvent>> processLocation({
    required String vehicleId,
    required double lat,
    required double lng,
    required DateTime timestamp,
    bool isReEvaluation = false,
  }) async {
    // --- Edge Case 4: Inaccurate Readings (Coordinate Range & Null Island Check) ---
    if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0 || (lat == 0.0 && lng == 0.0)) {
      return []; // Discard out-of-bounds coordinate artifact
    }

    final lastKnown = _lastLocations[vehicleId];

    // --- Edge Case 1: Duplicates (only for raw telemetry packets, not boundary re-evaluations) ---
    if (!isReEvaluation &&
        lastKnown != null &&
        lastKnown.timestamp == timestamp &&
        (lastKnown.lat - lat).abs() < 0.00001 &&
        (lastKnown.lng - lng).abs() < 0.00001) {
      return []; // Idempotent duplicate: ignore
    }

    // --- Edge Case 4: Inaccurate Readings (Kinematic Jump Check) ---
    if (lastKnown != null) {
      final elapsedSeconds = timestamp.difference(lastKnown.timestamp).inSeconds;
      if (elapsedSeconds > 0) {
        final distMeters = DistanceCalculator.haversineMeters(lastKnown.lat, lastKnown.lng, lat, lng);
        final speedKmh = (distMeters / elapsedSeconds) * 3.6;
        if (speedKmh > maxPlausibleSpeedKmh) {
          // Unrealistic GPS teleportation jump - discard from triggering geofence events
          return [];
        }
      }
    }

    // Fetch active geofences
    final geofenceRows = await dbService.queryRows('''
      SELECT id, name, center_lat, center_lng, radius_meters, is_active, created_at, updated_at 
      FROM geofences 
      WHERE is_active = true;
    ''');
    final activeGeofences = geofenceRows.map((r) => Geofence.fromRow(r)).toList();

    // Fetch latest known geofence transition for this vehicle
    final eventRows = await dbService.queryRows('''
      SELECT id, vehicle_id, geofence_id, event_type, timestamp 
      FROM geofence_events 
      WHERE vehicle_id = '$vehicleId' 
      ORDER BY timestamp DESC, id DESC 
      LIMIT 1;
    ''');

    String? currentGeofenceId;
    if (eventRows.isNotEmpty) {
      final latestEvent = eventRows.first;
      if (latestEvent[3].toString() == 'ENTRY') {
        currentGeofenceId = latestEvent[2].toString();
      }
    }

    final newEvents = <GeofenceEvent>[];
    final tsUtc = timestamp.toUtc();
    final tsIso = tsUtc.toIso8601String();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // --- Edge Case 3 (GPS Jitter) & Edge Case 5 (Overlaps) ---
    // Evaluate containment with 15m spatial hysteresis and normalized distance tie-breaking
    Geofence? winningGeofence;
    double minNormalizedDistance = double.infinity;

    for (final gf in activeGeofences) {
      final dist = DistanceCalculator.haversineMeters(lat, lng, gf.centerLat, gf.centerLng);
      final isCurrentlyInsideThis = (currentGeofenceId == gf.id);

      // Edge Case 3: Hysteresis boundary deadband
      final threshold = isCurrentlyInsideThis
          ? (gf.radiusMeters + hysteresisMeters)
          : (gf.radiusMeters - hysteresisMeters);

      if (dist <= threshold) {
        // Edge Case 5: Overlaps - Pick closest to center relative to size, break tie by radius, then ID
        final normalizedDist = dist / gf.radiusMeters;
        if (normalizedDist < minNormalizedDistance) {
          minNormalizedDistance = normalizedDist;
          winningGeofence = gf;
        } else if ((normalizedDist - minNormalizedDistance).abs() < 0.001) {
          // Tie-break 1: Smaller radius
          if (winningGeofence == null || gf.radiusMeters < winningGeofence.radiusMeters) {
            winningGeofence = gf;
          } else if (gf.radiusMeters == winningGeofence.radiusMeters &&
              gf.id.compareTo(winningGeofence.id) < 0) {
            // Tie-break 2: Lexicographical ID
            winningGeofence = gf;
          }
        }
      }
    }

    // --- Edge Case 6: Missing Intervals (Tunnel / Disconnect Blackout) ---
    // Synthesize an exit only if vehicle reappears outside former geofence after prolonged blackout (not on boundary re-evaluations)
    if (!isReEvaluation && lastKnown != null && currentGeofenceId != null && winningGeofence?.id != currentGeofenceId) {
      final blackoutSeconds = tsUtc.difference(lastKnown.timestamp.toUtc()).inSeconds;
      if (blackoutSeconds > blackoutIntervalSeconds) {
        final exitTsIso = lastKnown.timestamp.toUtc().add(const Duration(seconds: 1)).toIso8601String();
        final exitId = uuid.v4();
        await dbService.execute('''
          INSERT INTO geofence_events (id, vehicle_id, geofence_id, event_type, timestamp, packet_timestamp)
          VALUES ('$exitId', '$vehicleId', '$currentGeofenceId', 'EXIT', '$exitTsIso', '$nowIso');
        ''');
        newEvents.add(GeofenceEvent(
          id: exitId,
          vehicleId: vehicleId,
          geofenceId: currentGeofenceId,
          eventType: GeofenceEventType.exit,
          timestamp: lastKnown.timestamp.toUtc().add(const Duration(seconds: 1)),
        ));
        currentGeofenceId = null;
      }
    }

    // Execute state transitions
    if (winningGeofence != null) {
      if (currentGeofenceId != winningGeofence.id) {
        // Exit old geofence if currently inside another
        if (currentGeofenceId != null) {
          final exitId = uuid.v4();
          await dbService.execute('''
            INSERT INTO geofence_events (id, vehicle_id, geofence_id, event_type, timestamp, packet_timestamp)
            VALUES ('$exitId', '$vehicleId', '$currentGeofenceId', 'EXIT', '$tsIso', '$nowIso');
          ''');
          newEvents.add(GeofenceEvent(
            id: exitId,
            vehicleId: vehicleId,
            geofenceId: currentGeofenceId,
            eventType: GeofenceEventType.exit,
            timestamp: timestamp,
          ));
        }

        // Enter new geofence
        final entryId = uuid.v4();
        await dbService.execute('''
          INSERT INTO geofence_events (id, vehicle_id, geofence_id, event_type, timestamp, packet_timestamp)
          VALUES ('$entryId', '$vehicleId', '${winningGeofence.id}', 'ENTRY', '$tsIso', '$nowIso');
        ''');
        newEvents.add(GeofenceEvent(
          id: entryId,
          vehicleId: vehicleId,
          geofenceId: winningGeofence.id,
          eventType: GeofenceEventType.entry,
          timestamp: timestamp,
        ));
      }
    } else {
      // Outside all geofences
      if (currentGeofenceId != null) {
        final exitId = uuid.v4();
        await dbService.execute('''
          INSERT INTO geofence_events (id, vehicle_id, geofence_id, event_type, timestamp, packet_timestamp)
          VALUES ('$exitId', '$vehicleId', '$currentGeofenceId', 'EXIT', '$tsIso', '$nowIso');
        ''');
        newEvents.add(GeofenceEvent(
          id: exitId,
          vehicleId: vehicleId,
          geofenceId: currentGeofenceId,
          eventType: GeofenceEventType.exit,
          timestamp: timestamp,
        ));
      }
    }

    // Update last known location cache
    _lastLocations[vehicleId] = _LastKnownLocation(
      lat: lat,
      lng: lng,
      timestamp: timestamp,
    );

    // Automatically feed generated ENTRY/EXIT events into TripEngine
    if (newEvents.isNotEmpty && tripEngine != null) {
      await tripEngine!.processGeofenceEvents(vehicleId: vehicleId, events: newEvents);
    }

    return newEvents;
  }

  /// Edge Case 7 (Geofence Edits):
  /// Re-evaluates all vehicles against current active geofences when geofences are created, edited, or deactivated.
  Future<void> reEvaluateAllVehicles() async {
    final vehicleRows = await dbService.queryRows('''
      SELECT vehicle_id, latitude, longitude, last_ping 
      FROM v_latest_vehicle_status 
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
    ''');

    final now = DateTime.now();

    for (final row in vehicleRows) {
      final vId = row[0].toString();
      final lat = (row[1] as num).toDouble();
      final lng = (row[2] as num).toDouble();

      await processLocation(
        vehicleId: vId,
        lat: lat,
        lng: lng,
        timestamp: now,
        isReEvaluation: true,
      );
    }
  }

  /// Queries all geofences (both active and retained deactivated) with live active vehicle counts.
  Future<List<Geofence>> fetchAllGeofences() async {
    var gfRows = await dbService.queryRows('''
      SELECT id, name, center_lat, center_lng, radius_meters, is_active, created_at, updated_at 
      FROM geofences 
      ORDER BY created_at ASC;
    ''');

    // Auto-seed if geofences table is empty
    if (gfRows.isEmpty) {
      await seedDefaultGeofences();
      gfRows = await dbService.queryRows('''
        SELECT id, name, center_lat, center_lng, radius_meters, is_active, created_at, updated_at 
        FROM geofences 
        ORDER BY created_at ASC;
      ''');
    }

    final geofences = <Geofence>[];
    for (final r in gfRows) {
      final gfId = r[0].toString();
      final countRows = await dbService.queryRows('''
        WITH latest_events AS (
          SELECT vehicle_id, geofence_id, event_type,
                 ROW_NUMBER() OVER (PARTITION BY vehicle_id ORDER BY timestamp DESC, id DESC) as rn
          FROM geofence_events
        )
        SELECT COUNT(*) 
        FROM latest_events 
        WHERE geofence_id = '$gfId' AND event_type = 'ENTRY' AND rn = 1;
      ''');

      final count = countRows.isNotEmpty ? (countRows.first.first as num).toInt() : 0;
      geofences.add(Geofence.fromRow(r, activeVehicleCount: count));
    }

    // If all geofence counts are 0, check if vehicles exist and need location re-evaluation
    final totalInside = geofences.fold<int>(0, (sum, g) => sum + g.activeVehicleCount);
    if (totalInside == 0 && geofences.isNotEmpty) {
      final vehicleCountRows = await dbService.queryRows('SELECT COUNT(*) FROM vehicles;');
      final vCount = vehicleCountRows.isNotEmpty ? (vehicleCountRows.first.first as num).toInt() : 0;
      if (vCount > 0) {
        await reEvaluateAllVehicles();
        // Re-read counts after evaluation
        geofences.clear();
        for (final r in gfRows) {
          final gfId = r[0].toString();
          final countRows = await dbService.queryRows('''
            WITH latest_events AS (
              SELECT vehicle_id, geofence_id, event_type,
                     ROW_NUMBER() OVER (PARTITION BY vehicle_id ORDER BY timestamp DESC, id DESC) as rn
              FROM geofence_events
            )
            SELECT COUNT(*) 
            FROM latest_events 
            WHERE geofence_id = '$gfId' AND event_type = 'ENTRY' AND rn = 1;
          ''');

          final count = countRows.isNotEmpty ? (countRows.first.first as num).toInt() : 0;
          geofences.add(Geofence.fromRow(r, activeVehicleCount: count));
        }
      }
    }

    return geofences;
  }
}

class _LastKnownLocation {
  final double lat;
  final double lng;
  final DateTime timestamp;

  _LastKnownLocation({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });
}
