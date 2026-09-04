import 'package:flutter_test/flutter_test.dart';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:dart_duckdb/open.dart';
import 'dart:io';
import 'package:fleet_console/core/database/duckdb_service.dart';
import 'package:fleet_console/core/engine/geofence_engine.dart';
import 'package:fleet_console/core/engine/trip_engine.dart';
import 'package:fleet_console/core/models/trip.dart';

void main() {
  late DuckDBService dbService;
  late GeofenceEngine geofenceEngine;
  late TripEngine tripEngine;

  setUpAll(() {
    if (Platform.isMacOS) {
      open.overrideFor(OperatingSystem.macOS, '/opt/homebrew/lib/libduckdb.dylib');
    }
  });

  setUp(() async {
    dbService = DuckDBService();
    await dbService.init(inMemory: true);
    geofenceEngine = GeofenceEngine(dbService);
    tripEngine = TripEngine(dbService);

    await geofenceEngine.seedDefaultGeofences();

    // Insert dummy vehicle
    await dbService.execute('''
      INSERT INTO vehicles (id, reg_number, model, created_at)
      VALUES ('v200', 'KA-02-E-2020', 'Mahindra Treo', '${DateTime.now().toIso8601String()}');
    ''');
  });

  tearDown(() async {
    await dbService.dispose();
  });

  group('Geofence & Automatic Trip Engine Tests', () {
    final now = DateTime.now();

    test('Exit from Depot Alpha starts an IN_PROGRESS trip', () async {
      // 1. Vehicle starts inside Depot Alpha (12.9716, 77.5946)
      await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9716,
        lng: 77.5946,
        timestamp: now,
      );

      // 2. Vehicle moves outside Depot Alpha to open road (12.9500, 77.6200)
      final exitEvents = await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9500,
        lng: 77.6200,
        timestamp: now.add(const Duration(minutes: 5)),
      );

      expect(exitEvents.length, equals(1));
      expect(exitEvents.first.eventType.label, equals('EXIT'));

      // Process geofence exit in TripEngine
      await tripEngine.processGeofenceEvents(
        vehicleId: 'v200',
        events: exitEvents,
      );

      final trips = await tripEngine.fetchVehicleTrips('v200');
      expect(trips.length, equals(1));
      expect(trips.first.status, equals(TripStatus.inProgress));
      expect(trips.first.originGeofenceName, equals('Depot Alpha'));
    });

    test('Next entry to Charging Hub East completes active trip with distance', () async {
      // 1. Enter and exit Depot Alpha
      await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9716,
        lng: 77.5946,
        timestamp: now,
      );

      final exitEvents = await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9500,
        lng: 77.6200,
        timestamp: now.add(const Duration(minutes: 5)),
      );
      await tripEngine.processGeofenceEvents(vehicleId: 'v200', events: exitEvents);

      // 2. Vehicle enters Charging Hub East (12.9250, 77.6800)
      final entryEvents = await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9250,
        lng: 77.6800,
        timestamp: now.add(const Duration(minutes: 20)),
      );

      expect(entryEvents.length, equals(1));
      expect(entryEvents.first.eventType.label, equals('ENTRY'));

      // Process entry in TripEngine
      await tripEngine.processGeofenceEvents(vehicleId: 'v200', events: entryEvents);

      final trips = await tripEngine.fetchVehicleTrips('v200');
      expect(trips.length, equals(1));
      expect(trips.first.status, equals(TripStatus.completed));
      expect(trips.first.originGeofenceName, equals('Depot Alpha'));
      expect(trips.first.destinationGeofenceName, equals('Charging Hub East'));
      expect(trips.first.distanceKm, greaterThan(0.0));
    });
  });
}
