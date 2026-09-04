import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:dart_duckdb/open.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'schema.dart';

class DuckDBService {
  Database? _db;
  Connection? _connection;
  bool _isInitialized = false;
  String? _dbPath;

  Database get db => _db!;
  Connection get conn => _connection!;
  bool get isInitialized => _isInitialized;
  String? get dbPath => _dbPath;

  /// Initializes DuckDB database instance.
  /// If [inMemory] is true, uses an in-memory database (:memory:).
  /// Otherwise, creates or opens a persistent DuckDB file on disk.
  Future<void> init({bool inMemory = false, String? customPath}) async {
    if (_isInitialized) return;

    _setupPlatformLibrary();

    if (inMemory) {
      _dbPath = ':memory:';
    } else if (customPath != null) {
      _dbPath = customPath;
    } else {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbDir = Directory(p.join(appDocDir.path, 'fleet_console_data'));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
      _dbPath = p.join(dbDir.path, 'fleet_telemetry.duckdb');
    }

    debugPrint('Initializing DuckDB database at: $_dbPath');
    _db = await duckdb.open(_dbPath!);
    _connection = await duckdb.connect(_db!);

    await _createTables();
    _isInitialized = true;
  }

  void _setupPlatformLibrary() {
    try {
      if (Platform.isMacOS) {
        // macOS homebrew / test fallback path
        const macLib = '/opt/homebrew/lib/libduckdb.dylib';
        if (File(macLib).existsSync()) {
          open.overrideFor(OperatingSystem.macOS, macLib);
        }
      }
    } catch (_) {
      // Ignored if platform or open fails in web/test environment
    }
  }

  Future<void> _createTables() async {
    await conn.execute(DatabaseSchema.createVehiclesTable);
    await conn.execute(DatabaseSchema.createTelemetrySignalsTable);
    await conn.execute(DatabaseSchema.createTelemetryIndexes);
    await conn.execute(DatabaseSchema.createGeofencesTable);
    await conn.execute(DatabaseSchema.createGeofenceEventsTable);
    await conn.execute(DatabaseSchema.createGeofenceEventsIndex);
    await conn.execute(DatabaseSchema.createTripsTable);
    await conn.execute(DatabaseSchema.createTripsIndex);
    await conn.execute(DatabaseSchema.createAlertsTable);
    await conn.execute(DatabaseSchema.createAlertsIndex);
    await conn.execute(DatabaseSchema.createLatestVehicleStatusView);
  }

  Future<void> execute(String query) async {
    await conn.execute(query);
  }

  Future<ResultSet> query(String query) async {
    return await conn.query(query);
  }

  Future<List<List<Object?>>> queryRows(String query) async {
    final rs = await conn.query(query);
    final rows = rs.fetchAll();
    await rs.dispose();
    return rows;
  }

  Future<void> dispose() async {
    if (_connection != null) {
      await _connection!.dispose();
      _connection = null;
    }
    if (_db != null) {
      await _db!.dispose();
      _db = null;
    }
    _isInitialized = false;
  }

  /// Clears all tables for clean test state
  Future<void> clearAllData() async {
    await conn.execute('DELETE FROM telemetry_signals;');
    await conn.execute('DELETE FROM geofence_events;');
    await conn.execute('DELETE FROM trips;');
    await conn.execute('DELETE FROM alerts;');
    await conn.execute('DELETE FROM geofences;');
    await conn.execute('DELETE FROM vehicles;');
  }
}
