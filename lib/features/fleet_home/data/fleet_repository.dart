import 'dart:math';
import 'package:uuid/uuid.dart';
import '../../../core/database/duckdb_service.dart';
import '../../../core/models/vehicle.dart';
import '../../../core/engine/alert_engine.dart';
import '../../../core/engine/geofence_engine.dart';
import '../../../core/engine/trip_engine.dart';

class FleetStatusCounts {
  final int allCount;
  final int movingCount;
  final int idleCount;
  final int stoppedCount;
  final int offlineCount;

  const FleetStatusCounts({
    required this.allCount,
    required this.movingCount,
    required this.idleCount,
    required this.stoppedCount,
    required this.offlineCount,
  });
}

class FleetRepository {
  final DuckDBService dbService;
  late final AlertEngine alertEngine;
  late final GeofenceEngine geofenceEngine;
  late final TripEngine tripEngine;
  final Uuid uuid = const Uuid();

  FleetRepository(this.dbService) {
    alertEngine = AlertEngine(dbService);
    geofenceEngine = GeofenceEngine(dbService);
    tripEngine = TripEngine(dbService);
  }

  /// Fetches list of vehicles directly from DuckDB view `v_latest_vehicle_status`
  /// joins current geofence status from latest geofence event
  Future<List<Vehicle>> fetchFleetList({
    String? statusFilter, // 'ALL', 'MOVING', 'IDLE', 'STOPPED', 'OFFLINE'
    String? searchQuery,
  }) async {
    final rows = await dbService.queryRows('''
      WITH latest_gf_events AS (
        SELECT 
          ge.vehicle_id, 
          ge.geofence_id, 
          ge.event_type,
          ROW_NUMBER() OVER (PARTITION BY ge.vehicle_id ORDER BY ge.timestamp DESC, ge.id DESC) as rn
        FROM geofence_events ge
      )
      SELECT 
        v.vehicle_id, v.reg_number, v.model, v.last_ping, 
        v.soc, v.range_km, v.speed, v.battery_temp, v.odometer, v.ignition, v.latitude, v.longitude,
        (SELECT COUNT(*) FROM alerts a WHERE a.vehicle_id = v.vehicle_id AND a.status = 'ACTIVE') as active_alerts,
        CASE WHEN lge.event_type = 'ENTRY' THEN gf.name ELSE NULL END as current_geofence_name
      FROM v_latest_vehicle_status v
      LEFT JOIN latest_gf_events lge ON v.vehicle_id = lge.vehicle_id AND lge.rn = 1
      LEFT JOIN geofences gf ON lge.geofence_id = gf.id
      ORDER BY v.reg_number ASC;
    ''');

    final now = DateTime.now();
    final vehicles = <Vehicle>[];

    for (final row in rows) {
      final activeAlertCount = (row[12] as num).toInt();
      final vehicle = Vehicle.fromRow(row, hasActiveAlert: activeAlertCount > 0);

      // Filter by status calculation in memory/SQL
      if (statusFilter != null && statusFilter.toUpperCase() != 'ALL') {
        final calcStatus = vehicle.calculateStatus(referenceTime: now).label;
        if (calcStatus != statusFilter.toUpperCase()) {
          continue;
        }
      }

      // Filter by search query
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        final matchReg = vehicle.regNumber.toLowerCase().contains(q);
        final matchModel = vehicle.model.toLowerCase().contains(q);
        if (!matchReg && !matchModel) {
          continue;
        }
      }

      vehicles.add(vehicle);
    }

    return vehicles;
  }

  /// Computes live status filter counts computed via SQL / status calculations
  Future<FleetStatusCounts> fetchStatusCounts() async {
    final vehicles = await fetchFleetList(statusFilter: 'ALL');
    final now = DateTime.now();

    int moving = 0;
    int idle = 0;
    int stopped = 0;
    int offline = 0;

    for (final v in vehicles) {
      final status = v.calculateStatus(referenceTime: now);
      switch (status) {
        case VehicleStatus.moving:
          moving++;
          break;
        case VehicleStatus.idle:
          idle++;
          break;
        case VehicleStatus.stopped:
          stopped++;
          break;
        case VehicleStatus.offline:
          offline++;
          break;
      }
    }

    return FleetStatusCounts(
      allCount: vehicles.length,
      movingCount: moving,
      idleCount: idle,
      stoppedCount: stopped,
      offlineCount: offline,
    );
  }

  /// Seeds initial 50 vehicles and baseline telemetry packets if database is empty
  Future<void> seedInitialDataIfEmpty() async {
    // 1. Always ensure default circular geofences are seeded
    await geofenceEngine.seedDefaultGeofences();

    final countRows = await dbService.queryRows('SELECT COUNT(*) FROM vehicles;');
    final count = (countRows.first.first as num).toInt();

    if (count == 0) {
      await seedVehicles(count: 50);
    }

    // 2. Ensure vehicles are assigned to geofences if no events exist
    final eventCountRows = await dbService.queryRows('SELECT COUNT(*) FROM geofence_events;');
    final eventCount = eventCountRows.isNotEmpty ? (eventCountRows.first.first as num).toInt() : 0;
    if (eventCount == 0) {
      await assignVehiclesToGeofences();
    }
  }

  /// Assigns vehicles to Depot Alpha, Charging Hub East, Logistics Terminal South, and in-transit
  Future<void> assignVehiclesToGeofences() async {
    final vehicleRows = await dbService.queryRows('SELECT id FROM vehicles ORDER BY id ASC;');
    if (vehicleRows.isEmpty) return;

    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final random = Random(42);

    int index = 1;
    for (final row in vehicleRows) {
      final vehicleId = row[0].toString();
      double lat;
      double lng;

      if (index <= 12) {
        // Depot Alpha (12.9716, 77.5946, radius 500m)
        lat = 12.9716 + (random.nextDouble() - 0.5) * 0.002;
        lng = 77.5946 + (random.nextDouble() - 0.5) * 0.002;
      } else if (index <= 22) {
        // Charging Hub East (12.9250, 77.6800, radius 400m)
        lat = 12.9250 + (random.nextDouble() - 0.5) * 0.002;
        lng = 77.6800 + (random.nextDouble() - 0.5) * 0.002;
      } else if (index <= 32) {
        // Logistics Terminal South (12.8500, 77.6500, radius 600m)
        lat = 12.8500 + (random.nextDouble() - 0.5) * 0.002;
        lng = 77.6500 + (random.nextDouble() - 0.5) * 0.002;
      } else {
        // In transit on highway
        lat = 12.9500 + (random.nextDouble() - 0.5) * 0.08;
        lng = 77.6200 + (random.nextDouble() - 0.5) * 0.08;
      }

      // Insert updated coordinates into telemetry_signals
      final latId = uuid.v4();
      final lngId = uuid.v4();
      await dbService.execute('''
        INSERT INTO telemetry_signals (id, vehicle_id, signal_name, value, unit, timestamp, ingested_at)
        VALUES 
          ('$latId', '$vehicleId', 'latitude', $lat, NULL, '$nowIso', '$nowIso'),
          ('$lngId', '$vehicleId', 'longitude', $lng, NULL, '$nowIso', '$nowIso');
      ''');

      // Process location in geofence engine to register ENTRY/EXIT transitions
      await geofenceEngine.processLocation(
        vehicleId: vehicleId,
        lat: lat,
        lng: lng,
        timestamp: now,
      );

      index++;
    }
  }

  /// Seeds N vehicles with sample telemetry signals into DuckDB
  Future<void> seedVehicles({required int count}) async {
    final now = DateTime.now();
    final random = Random(42);
    final models = ['Tata Ace EV', 'Ashok Leyland BOSS EV', 'Mahindra Treo', 'Eicher Pro 2055 EV', 'BYD T3'];

    for (int i = 1; i <= count; i++) {
      final vehicleId = 'veh_$i';
      final regNumber = 'KA-${(i % 50 + 10).toString().padLeft(2, '0')}-E-${(1000 + i)}';
      final model = models[i % models.length];
      final createdIso = now.subtract(Duration(days: 30)).toIso8601String();

      await dbService.execute('''
        INSERT INTO vehicles (id, reg_number, model, created_at)
        VALUES ('$vehicleId', '$regNumber', '$model', '$createdIso');
      ''');

      // Telemetry values scenario
      final isOffline = (i % 7 == 0);
      final isLowBattery = (i % 6 == 0);
      final isCriticalBattery = (i % 11 == 0);
      final isOverheating = (i % 13 == 0);

      final pingAgeMinutes = isOffline ? (15 + random.nextInt(120)) : random.nextInt(8);
      final pingTime = now.subtract(Duration(minutes: pingAgeMinutes));
      final pingIso = pingTime.toIso8601String();

      double soc = 75.0 + random.nextDouble() * 20.0;
      if (isCriticalBattery) soc = 8.0;
      else if (isLowBattery) soc = 16.0;

      final speed = (i % 3 == 0) ? (30.0 + random.nextDouble() * 40.0) : 0.0;
      final ignition = (speed > 0) || (i % 2 == 0);
      final temp = isOverheating ? 48.5 : (28.0 + random.nextDouble() * 12.0);
      final range = (soc * 2.2);
      final odo = 1200.0 + i * 150.0;

      // Seed deterministic positions: some inside each geofence, some in transit
      double lat;
      double lng;
      if (i <= 12) {
        // Depot Alpha (center: 12.9716, 77.5946)
        lat = 12.9716 + (random.nextDouble() - 0.5) * 0.002;
        lng = 77.5946 + (random.nextDouble() - 0.5) * 0.002;
      } else if (i <= 22) {
        // Charging Hub East (center: 12.9250, 77.6800)
        lat = 12.9250 + (random.nextDouble() - 0.5) * 0.002;
        lng = 77.6800 + (random.nextDouble() - 0.5) * 0.002;
      } else if (i <= 32) {
        // Logistics Terminal South (center: 12.8500, 77.6500)
        lat = 12.8500 + (random.nextDouble() - 0.5) * 0.002;
        lng = 77.6500 + (random.nextDouble() - 0.5) * 0.002;
      } else {
        // In transit on highway / outside geofences
        lat = 12.9500 + (random.nextDouble() - 0.5) * 0.08;
        lng = 77.6200 + (random.nextDouble() - 0.5) * 0.08;
      }

      final signals = {
        'soc': soc,
        'range': range,
        'speed': speed,
        'battery_temp': temp,
        'odometer': odo,
        'ignition': ignition ? 1.0 : 0.0,
        'latitude': lat,
        'longitude': lng,
      };

      for (final entry in signals.entries) {
        final sigId = uuid.v4();
        await dbService.execute('''
          INSERT INTO telemetry_signals (id, vehicle_id, signal_name, value, unit, timestamp, ingested_at)
          VALUES ('$sigId', '$vehicleId', '${entry.key}', ${entry.value}, NULL, '$pingIso', '$pingIso');
        ''');
      }

      // Process geofence containment for vehicle
      await geofenceEngine.processLocation(
        vehicleId: vehicleId,
        lat: lat,
        lng: lng,
        timestamp: pingTime,
      );

      // Evaluate alerts for freshly ingested telemetry
      if (!isOffline) {
        await alertEngine.evaluateTelemetry(
          vehicleId: vehicleId,
          soc: soc,
          batteryTemp: temp,
          timestamp: pingTime,
        );
      }
    }
  }
}
