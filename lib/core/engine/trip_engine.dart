import 'package:uuid/uuid.dart';
import '../database/duckdb_service.dart';
import '../models/geofence.dart';
import '../models/trip.dart';
import '../utils/distance_calculator.dart';

class TripEngine {
  final DuckDBService dbService;
  final Uuid uuid = const Uuid();

  TripEngine(this.dbService);

  /// Processes geofence events for a vehicle and updates automatic trip status idempotently.
  Future<void> processGeofenceEvents({
    required String vehicleId,
    required List<GeofenceEvent> events,
  }) async {
    for (final event in events) {
      if (event.eventType == GeofenceEventType.exit) {
        await _handleConfirmedExit(event);
      } else if (event.eventType == GeofenceEventType.entry) {
        await _handleConfirmedEntry(event);
      }
    }
  }

  Future<void> _handleConfirmedExit(GeofenceEvent exitEvent) async {
    // Check if vehicle already has an IN_PROGRESS trip
    final activeTripRows = await dbService.queryRows('''
      SELECT id FROM trips 
      WHERE vehicle_id = '${exitEvent.vehicleId}' AND status = 'IN_PROGRESS' 
      LIMIT 1;
    ''');

    if (activeTripRows.isEmpty) {
      // Create new active trip starting at exit timestamp
      final tripId = uuid.v4();
      final startIso = exitEvent.timestamp.toIso8601String();
      await dbService.execute('''
        INSERT INTO trips (id, vehicle_id, origin_geofence_id, start_time, status, distance_km)
        VALUES ('$tripId', '${exitEvent.vehicleId}', '${exitEvent.geofenceId}', '$startIso', 'IN_PROGRESS', 0.0);
      ''');
    }
  }

  Future<void> _handleConfirmedEntry(GeofenceEvent entryEvent) async {
    // Check for active IN_PROGRESS trip for this vehicle
    final activeTripRows = await dbService.queryRows('''
      SELECT id, origin_geofence_id, start_time FROM trips 
      WHERE vehicle_id = '${entryEvent.vehicleId}' AND status = 'IN_PROGRESS' 
      LIMIT 1;
    ''');

    if (activeTripRows.isNotEmpty) {
      final tripId = activeTripRows[0][0].toString();
      final originId = activeTripRows[0][1].toString();
      final endIso = entryEvent.timestamp.toIso8601String();

      // Calculate distance between origin and destination geofences
      double distanceKm = 0.0;
      final originCoords = await dbService.queryRows('SELECT center_lat, center_lng FROM geofences WHERE id = \'$originId\';');
      final destCoords = await dbService.queryRows('SELECT center_lat, center_lng FROM geofences WHERE id = \'${entryEvent.geofenceId}\';');
      if (originCoords.isNotEmpty && destCoords.isNotEmpty) {
        final originLat = (originCoords[0][0] as num).toDouble();
        final originLng = (originCoords[0][1] as num).toDouble();
        final destLat = (destCoords[0][0] as num).toDouble();
        final destLng = (destCoords[0][1] as num).toDouble();
        distanceKm = DistanceCalculator.haversineKm(originLat, originLng, destLat, destLng);
      }

      await dbService.execute('''
        UPDATE trips 
        SET status = 'COMPLETED', destination_geofence_id = '${entryEvent.geofenceId}', end_time = '$endIso', distance_km = $distanceKm 
        WHERE id = '$tripId';
      ''');
    }
  }

  /// Seeds realistic initial automatic trips if trips table is empty
  Future<void> seedDefaultTripsIfEmpty() async {
    final tripCountRows = await dbService.queryRows('SELECT COUNT(*) FROM trips;');
    final tripCount = tripCountRows.isNotEmpty ? (tripCountRows.first.first as num).toInt() : 0;
    if (tripCount > 0) return;

    final now = DateTime.now();
    final tripsToSeed = <Map<String, dynamic>>[];

    // 1. veh_1 to veh_12 (Depot Alpha vehicles)
    for (int i = 1; i <= 12; i++) {
      final vId = 'veh_$i';
      final startHoursAgo = 2 + (i % 4);
      final durationMins = 32 + (i * 3) % 20;
      final startTime = now.subtract(Duration(hours: startHoursAgo));
      final endTime = startTime.add(Duration(minutes: durationMins));

      tripsToSeed.add({
        'id': uuid.v4(),
        'vehicle_id': vId,
        'origin_geofence_id': (i % 2 == 0) ? 'geo_2' : 'geo_3',
        'destination_geofence_id': 'geo_1',
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'status': 'COMPLETED',
        'distance_km': (i % 2 == 0) ? 10.8 : 14.2,
      });

      final yesterdayStart = startTime.subtract(const Duration(days: 1));
      final yesterdayEnd = yesterdayStart.add(Duration(minutes: durationMins));
      tripsToSeed.add({
        'id': uuid.v4(),
        'vehicle_id': vId,
        'origin_geofence_id': 'geo_1',
        'destination_geofence_id': (i % 2 == 0) ? 'geo_2' : 'geo_3',
        'start_time': yesterdayStart.toIso8601String(),
        'end_time': yesterdayEnd.toIso8601String(),
        'status': 'COMPLETED',
        'distance_km': (i % 2 == 0) ? 10.8 : 14.2,
      });
    }

    // 2. veh_13 to veh_22 (Charging Hub East vehicles)
    for (int i = 13; i <= 22; i++) {
      final vId = 'veh_$i';
      final startHoursAgo = 3 + (i % 3);
      final startTime = now.subtract(Duration(hours: startHoursAgo));
      final endTime = startTime.add(const Duration(minutes: 40));

      tripsToSeed.add({
        'id': uuid.v4(),
        'vehicle_id': vId,
        'origin_geofence_id': 'geo_1',
        'destination_geofence_id': 'geo_2',
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'status': 'COMPLETED',
        'distance_km': 11.4,
      });
    }

    // 3. veh_23 to veh_32 (Logistics Terminal South vehicles)
    for (int i = 23; i <= 32; i++) {
      final vId = 'veh_$i';
      final startHoursAgo = 4 + (i % 3);
      final startTime = now.subtract(Duration(hours: startHoursAgo));
      final endTime = startTime.add(const Duration(minutes: 48));

      tripsToSeed.add({
        'id': uuid.v4(),
        'vehicle_id': vId,
        'origin_geofence_id': 'geo_2',
        'destination_geofence_id': 'geo_3',
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'status': 'COMPLETED',
        'distance_km': 9.6,
      });
    }

    // 4. veh_33 to veh_50 (In-transit vehicles)
    for (int i = 33; i <= 50; i++) {
      final vId = 'veh_$i';
      final departedMinutesAgo = 20 + (i * 3) % 40;
      final startTime = now.subtract(Duration(minutes: departedMinutesAgo));
      final originId = (i % 3 == 0) ? 'geo_1' : (i % 3 == 1 ? 'geo_2' : 'geo_3');

      tripsToSeed.add({
        'id': uuid.v4(),
        'vehicle_id': vId,
        'origin_geofence_id': originId,
        'destination_geofence_id': null,
        'start_time': startTime.toIso8601String(),
        'end_time': null,
        'status': 'IN_PROGRESS',
        'distance_km': 0.0,
      });
    }

    for (final t in tripsToSeed) {
      final destSql = t['destination_geofence_id'] == null ? 'NULL' : "'${t['destination_geofence_id']}'";
      final endSql = t['end_time'] == null ? 'NULL' : "'${t['end_time']}'";
      await dbService.execute('''
        INSERT INTO trips (id, vehicle_id, origin_geofence_id, destination_geofence_id, start_time, end_time, status, distance_km)
        VALUES ('${t['id']}', '${t['vehicle_id']}', '${t['origin_geofence_id']}', $destSql, '${t['start_time']}', $endSql, '${t['status']}', ${t['distance_km']});
      ''');
    }
  }

  /// Queries all trips for a vehicle with resolved origin & destination geofence names
  Future<List<Trip>> fetchVehicleTrips(String vehicleId) async {
    await seedDefaultTripsIfEmpty();

    final rows = await dbService.queryRows('''
      SELECT 
        t.id, t.vehicle_id, t.origin_geofence_id, t.destination_geofence_id, 
        t.start_time, t.end_time, t.status, t.distance_km,
        og.name as origin_name, dg.name as dest_name
      FROM trips t
      LEFT JOIN geofences og ON t.origin_geofence_id = og.id
      LEFT JOIN geofences dg ON t.destination_geofence_id = dg.id
      WHERE t.vehicle_id = '$vehicleId'
      ORDER BY t.start_time DESC;
    ''');

    return rows.map((r) {
      final originName = r[8]?.toString() ?? 'Unknown Location';
      final destName = r[9]?.toString() ?? (r[6].toString() == 'IN_PROGRESS' ? 'In Progress' : 'Unknown Location');
      return Trip.fromRow(r, originName: originName, destName: destName);
    }).toList();
  }
}
