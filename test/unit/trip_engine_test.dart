import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:dart_duckdb/open.dart';
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
    await geofenceEngine.seedDefaultGeofences();
    tripEngine = TripEngine(dbService);
  });

  tearDown(() async {
    await dbService.dispose();
  });

  test('Automatic Trips: seedDefaultTripsIfEmpty populates completed and in-progress trips with distance and geofence names', () async {
    // Check initial trips for veh_1 (Depot Alpha vehicle)
    final tripsVeh1 = await tripEngine.fetchVehicleTrips('veh_1');
    expect(tripsVeh1.length, equals(2));
    expect(tripsVeh1.first.status, equals(TripStatus.completed));
    expect(tripsVeh1.first.distanceKm, greaterThan(5.0));
    expect(tripsVeh1.first.originGeofenceName, isNotEmpty);
    expect(tripsVeh1.first.destinationGeofenceName, isNotEmpty);

    // Check in-progress trip for highway transit vehicle veh_33
    final tripsVeh33 = await tripEngine.fetchVehicleTrips('veh_33');
    expect(tripsVeh33.length, equals(1));
    expect(tripsVeh33.first.status, equals(TripStatus.inProgress));
    expect(tripsVeh33.first.destinationGeofenceName, equals('In Progress'));
  });
}
