import 'package:flutter_test/flutter_test.dart';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:dart_duckdb/open.dart';
import 'dart:io';
import 'package:fleet_console/core/database/duckdb_service.dart';
import 'package:fleet_console/core/engine/geofence_engine.dart';
import 'package:fleet_console/features/fleet_home/data/fleet_repository.dart';

void main() {
  late DuckDBService dbService;
  late FleetRepository fleetRepo;

  setUpAll(() {
    if (Platform.isMacOS) {
      open.overrideFor(OperatingSystem.macOS, '/opt/homebrew/lib/libduckdb.dylib');
    }
  });

  setUp(() async {
    dbService = DuckDBService();
    await dbService.init(inMemory: true);
    fleetRepo = FleetRepository(dbService);
    await fleetRepo.seedInitialDataIfEmpty();
  });

  tearDown(() async {
    await dbService.dispose();
  });

  test('Reproduce geofence toggle issue', () async {
    // 1. Fetch initial geofences
    var gfs = await fleetRepo.geofenceEngine.fetchAllGeofences();
    print('INITIAL GEOFENCES:');
    for (final g in gfs) {
      print('${g.id} (${g.name}): active=${g.isActive}, count=${g.activeVehicleCount}');
    }

    // Print veh_13 status
    final v13Before = await dbService.queryRows('''
      SELECT vehicle_id, latitude, longitude, last_ping FROM v_latest_vehicle_status WHERE vehicle_id = 'veh_13';
    ''');
    print('veh_13 BEFORE TOGGLE in v_latest_vehicle_status: $v13Before');

    // 2. Toggle off Depot Alpha
    final depotAlpha = gfs.firstWhere((g) => g.name == 'Depot Alpha');
    print('\nTOGGLING OFF Depot Alpha (${depotAlpha.id})...');
    await fleetRepo.geofenceEngine.updateGeofence(
      id: depotAlpha.id,
      name: depotAlpha.name,
      centerLat: depotAlpha.centerLat,
      centerLng: depotAlpha.centerLng,
      radiusMeters: depotAlpha.radiusMeters,
      isActive: false,
    );

    // 3. Fetch geofences after toggle OFF
    gfs = await fleetRepo.geofenceEngine.fetchAllGeofences();
    print('\nGEOFENCES AFTER TOGGLE OFF:');
    for (final g in gfs) {
      print('${g.id} (${g.name}): active=${g.isActive}, count=${g.activeVehicleCount}');
    }

    final depotAlphaOff = gfs.firstWhere((g) => g.name == 'Depot Alpha');
    final chargingHub = gfs.firstWhere((g) => g.name == 'Charging Hub East');
    final logisticsTerminal = gfs.firstWhere((g) => g.name == 'Logistics Terminal South');

    expect(depotAlphaOff.isActive, isFalse);
    expect(depotAlphaOff.activeVehicleCount, equals(0));
    expect(chargingHub.isActive, isTrue);
    expect(chargingHub.activeVehicleCount, equals(10), reason: 'Charging Hub East count must stay 10');
    expect(logisticsTerminal.isActive, isTrue);
    expect(logisticsTerminal.activeVehicleCount, equals(10), reason: 'Logistics Terminal South count must stay 10');

    // 4. Toggle back ON
    print('\nTOGGLING BACK ON Depot Alpha...');
    await fleetRepo.geofenceEngine.updateGeofence(
      id: depotAlpha.id,
      name: depotAlpha.name,
      centerLat: depotAlpha.centerLat,
      centerLng: depotAlpha.centerLng,
      radiusMeters: depotAlpha.radiusMeters,
      isActive: true,
    );

    gfs = await fleetRepo.geofenceEngine.fetchAllGeofences();
    final depotAlphaOn = gfs.firstWhere((g) => g.name == 'Depot Alpha');
    expect(depotAlphaOn.isActive, isTrue);
    expect(depotAlphaOn.activeVehicleCount, equals(12), reason: 'Depot Alpha count must return to 12 when reactivated');
  });
}
