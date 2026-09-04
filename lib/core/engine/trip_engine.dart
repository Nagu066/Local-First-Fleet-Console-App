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
      final coordsRows = await dbService.queryRows('''
        SELECT center_lat, center_lng FROM geofences WHERE id IN ('$originId', '${entryEvent.geofenceId}');
      ''');

      if (coordsRows.length >= 2) {
        final originLat = (coordsRows[0][0] as num).toDouble();
        final originLng = (coordsRows[0][1] as num).toDouble();
        final destLat = (coordsRows[1][0] as num).toDouble();
        final destLng = (coordsRows[1][1] as num).toDouble();
        distanceKm = DistanceCalculator.haversineKm(originLat, originLng, destLat, destLng);
      }

      await dbService.execute('''
        UPDATE trips 
        SET status = 'COMPLETED', destination_geofence_id = '${entryEvent.geofenceId}', end_time = '$endIso', distance_km = $distanceKm 
        WHERE id = '$tripId';
      ''');
    }
  }

  /// Queries all trips for a vehicle with resolved origin & destination geofence names
  Future<List<Trip>> fetchVehicleTrips(String vehicleId) async {
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
