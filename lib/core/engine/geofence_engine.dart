import 'package:uuid/uuid.dart';
import '../database/duckdb_service.dart';
import '../models/geofence.dart';
import '../utils/distance_calculator.dart';

class GeofenceEngine {
  final DuckDBService dbService;
  final Uuid uuid = const Uuid();

  GeofenceEngine(this.dbService);

  /// Seed default geofences if none exist in DuckDB
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

  /// Processes GPS telemetry point (lat, lng) for vehicle at event-time [timestamp].
  /// Returns list of newly triggered [GeofenceEvent] transitions.
  Future<List<GeofenceEvent>> processLocation({
    required String vehicleId,
    required double lat,
    required double lng,
    required DateTime timestamp,
  }) async {
    // 1. Fetch all active geofences
    final geofenceRows = await dbService.queryRows('''
      SELECT id, name, center_lat, center_lng, radius_meters, is_active, created_at, updated_at 
      FROM geofences 
      WHERE is_active = true;
    ''');
    final activeGeofences = geofenceRows.map((r) => Geofence.fromRow(r)).toList();

    // 2. Fetch last known geofence events for vehicle ordered by timestamp DESC
    final eventRows = await dbService.queryRows('''
      SELECT id, vehicle_id, geofence_id, event_type, timestamp 
      FROM geofence_events 
      WHERE vehicle_id = '$vehicleId' 
      ORDER BY timestamp DESC, id DESC 
      LIMIT 10;
    ''');

    // Determine current active geofence for vehicle based on latest transition
    String? currentGeofenceId;
    if (eventRows.isNotEmpty) {
      final latestEvent = eventRows.first;
      final type = latestEvent[3].toString();
      if (type == 'ENTRY') {
        currentGeofenceId = latestEvent[2].toString();
      }
    }

    final newEvents = <GeofenceEvent>[];
    final tsIso = timestamp.toIso8601String();
    final nowIso = DateTime.now().toIso8601String();

    // 3. Find matching geofence at (lat, lng)
    Geofence? matchingGeofence;
    double minDistance = double.infinity;

    for (final gf in activeGeofences) {
      final isInside = DistanceCalculator.isInsideGeofence(
        lat: lat,
        lng: lng,
        centerLat: gf.centerLat,
        centerLng: gf.centerLng,
        radiusMeters: gf.radiusMeters,
        currentlyInside: (currentGeofenceId == gf.id),
      );

      if (isInside) {
        final dist = DistanceCalculator.haversineMeters(lat, lng, gf.centerLat, gf.centerLng);
        if (dist < minDistance) {
          minDistance = dist;
          matchingGeofence = gf;
        }
      }
    }

    if (matchingGeofence != null) {
      if (currentGeofenceId != matchingGeofence.id) {
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
          VALUES ('$entryId', '$vehicleId', '${matchingGeofence.id}', 'ENTRY', '$tsIso', '$nowIso');
        ''');
        newEvents.add(GeofenceEvent(
          id: entryId,
          vehicleId: vehicleId,
          geofenceId: matchingGeofence.id,
          eventType: GeofenceEventType.entry,
          timestamp: timestamp,
        ));
      }
    } else {
      // Vehicle is in open space outside all active geofences
      if (currentGeofenceId != null) {
        // Exit current geofence
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

    return newEvents;
  }

  /// Queries all geofences with live active vehicle counts
  Future<List<Geofence>> fetchAllGeofences() async {
    final gfRows = await dbService.queryRows('''
      SELECT id, name, center_lat, center_lng, radius_meters, is_active, created_at, updated_at 
      FROM geofences 
      ORDER BY created_at ASC;
    ''');

    final geofences = <Geofence>[];
    for (final r in gfRows) {
      final gfId = r[0].toString();
      final countRows = await dbService.queryRows('''
        WITH latest_events AS (
          SELECT vehicle_id, geofence_id, event_type,
                 ROW_NUMBER() OVER (PARTITION BY vehicle_id ORDER BY timestamp DESC) as rn
          FROM geofence_events
        )
        SELECT COUNT(*) 
        FROM latest_events 
        WHERE geofence_id = '$gfId' AND event_type = 'ENTRY' AND rn = 1;
      ''');

      final count = countRows.isNotEmpty ? (countRows.first.first as num).toInt() : 0;
      geofences.add(Geofence.fromRow(r, activeVehicleCount: count));
    }

    return geofences;
  }
}
