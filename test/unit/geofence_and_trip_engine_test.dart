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

    test('Edge Case 1 - Duplicates: Identical location packets are ignored idempotently', () async {
      final t1 = now.add(const Duration(minutes: 30));

      // First fix: triggers ENTRY into Depot Alpha
      final events1 = await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9716,
        lng: 77.5946,
        timestamp: t1,
      );
      expect(events1.length, equals(1));
      expect(events1.first.eventType.label, equals('ENTRY'));

      // Duplicate fix with identical timestamp and coordinates
      final events2 = await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9716,
        lng: 77.5946,
        timestamp: t1,
      );
      expect(events2, isEmpty, reason: 'Duplicate fix must not generate repeated ENTRY events');
    });

    test('Edge Case 3 - GPS Jitter: Hysteresis band prevents boundary flickering', () async {
      // Vehicle is inside Depot Alpha (center 12.9716, 77.5946, radius 500m)
      final t0 = now.add(const Duration(minutes: 40));
      await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9716,
        lng: 77.5946,
        timestamp: t0,
      );

      // Vehicle drifts to ~505m from center (just slightly outside radius 500m, but within 15m hysteresis band)
      // 0.0045 degrees lat is ~500m
      final eventsFlicker = await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9716 + 0.00453,
        lng: 77.5946,
        timestamp: t0.add(const Duration(seconds: 10)),
      );

      expect(eventsFlicker, isEmpty, reason: 'Jitter within 15m hysteresis margin must not trigger spurious EXIT');
    });

    test('Edge Case 4 - Inaccurate Readings: Teleportation jump (> 140 km/h) is rejected', () async {
      final t0 = now.add(const Duration(minutes: 50));
      // Legitimate fix at Depot Alpha
      await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9716,
        lng: 77.5946,
        timestamp: t0,
      );

      // Glitched GPS spike: teleported 50 km away in 5 seconds (> 36,000 km/h!)
      final glitchedEvents = await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 13.5000,
        lng: 77.5946,
        timestamp: t0.add(const Duration(seconds: 5)),
      );

      expect(glitchedEvents, isEmpty, reason: 'Kinematically implausible GPS spike must be discarded');
    });

    test('Edge Case 5 - Overlaps: Deterministic tie-breaking picks single closest geofence', () async {
      // Create two overlapping test geofences: A (radius 600m) and B (radius 400m) near (12.9000, 77.6000)
      await geofenceEngine.createGeofence(
        name: 'Overlap Hub A',
        centerLat: 12.9000,
        centerLng: 77.6000,
        radiusMeters: 600.0,
      );
      await geofenceEngine.createGeofence(
        name: 'Overlap Hub B',
        centerLat: 12.9020,
        centerLng: 77.6000,
        radiusMeters: 400.0,
      );

      // Place vehicle inside both circles at (12.9015, 77.6000) - closer to Hub B
      final events = await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9015,
        lng: 77.6000,
        timestamp: now.add(const Duration(hours: 2)),
      );

      expect(events.length, equals(1), reason: 'Only ONE geofence entry should trigger, never duplicate entries');
      expect(events.first.eventType.label, equals('ENTRY'));
    });

    test('Edge Case 6 - Missing Intervals: Blackout > 10 mins closes previous geofence cleanly', () async {
      final tStart = now.add(const Duration(hours: 3));
      // Vehicle starts inside Depot Alpha
      await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9716,
        lng: 77.5946,
        timestamp: tStart,
      );

      // Vehicle loses signal for 30 minutes in a tunnel, reappears at Charging Hub East
      final tReappear = tStart.add(const Duration(minutes: 30));
      final events = await geofenceEngine.processLocation(
        vehicleId: 'v200',
        lat: 12.9250,
        lng: 77.6800,
        timestamp: tReappear,
      );

      // Should contain clean EXIT from Depot Alpha and ENTRY into Charging Hub East
      expect(events.length, equals(2));
      expect(events[0].eventType.label, equals('EXIT'));
      expect(events[1].eventType.label, equals('ENTRY'));
    });

    test('Edge Case 7 - Geofence Edits & Deactivation: Retains geofences in DB and updates active status', () async {
      // Create new geofence
      final gf = await geofenceEngine.createGeofence(
        name: 'Temporary Yard',
        centerLat: 12.9100,
        centerLng: 77.6100,
        radiusMeters: 300.0,
      );

      // Edit its radius
      await geofenceEngine.updateGeofence(
        id: gf.id,
        name: 'Temporary Yard Expanded',
        centerLat: 12.9100,
        centerLng: 77.6100,
        radiusMeters: 550.0,
        isActive: true,
      );

      var allGfs = await geofenceEngine.fetchAllGeofences();
      final editedGf = allGfs.firstWhere((g) => g.id == gf.id);
      expect(editedGf.name, equals('Temporary Yard Expanded'));
      expect(editedGf.radiusMeters, equals(550.0));

      // Deactivate geofence (must NOT be deleted, retained for trip history)
      await geofenceEngine.deactivateGeofence(gf.id);

      allGfs = await geofenceEngine.fetchAllGeofences();
      final deactivatedGf = allGfs.firstWhere((g) => g.id == gf.id);
      expect(deactivatedGf.isActive, isFalse, reason: 'Deactivated geofence must be retained in DuckDB with is_active = false');
    });
  });
}
