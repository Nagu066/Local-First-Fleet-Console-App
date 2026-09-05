import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:uuid/uuid.dart';
import '../../../core/database/duckdb_service.dart';

class BenchmarkReport {
  final int vehicleCount;
  final int totalSignalRows;
  final double backfillDurationSeconds;
  final double p50QueryLatencyMs;
  final double p95QueryLatencyMs;
  final double memoryUsageMb;

  const BenchmarkReport({
    required this.vehicleCount,
    required this.totalSignalRows,
    required this.backfillDurationSeconds,
    required this.p50QueryLatencyMs,
    required this.p95QueryLatencyMs,
    required this.memoryUsageMb,
  });
}

class ScaleGenerator {
  final DuckDBService dbService;
  final Uuid uuid = const Uuid();

  /// Concurrency lock to prevent multiple benchmark backfills from running simultaneously
  static bool isRunning = false;

  ScaleGenerator(this.dbService);

  /// Backfills 500 vehicles and 2,000,000+ signal rows into DuckDB in high-speed batches.
  /// [onProgress] receives progress percentage (0.0 to 1.0) and status message.
  Future<BenchmarkReport> runScaleBackfillAndBenchmark({
    void Function(double progress, String status)? onProgress,
  }) async {
    if (isRunning) {
      throw StateError('A scale benchmark is already in progress.');
    }
    isRunning = true;

    try {
      onProgress?.call(0.01, 'Clearing existing test data...');
      await dbService.clearAllData();

      final stopwatch = Stopwatch()..start();
      const targetVehicles = 500;
      const rowsPerVehicle = 4000; // 500 * 4000 = 2,000,000 signal rows
      const totalSignalsTarget = targetVehicles * rowsPerVehicle;

      onProgress?.call(0.05, 'Inserting 500 vehicles...');
      final now = DateTime.now();
      final runEpoch = now.millisecondsSinceEpoch;

      // 1. Insert 500 vehicles in a single batch statement with conflict handling
      final vehicleSql = StringBuffer('INSERT INTO vehicles (id, reg_number, model, created_at) VALUES ');
      for (int i = 1; i <= targetVehicles; i++) {
        final vId = 'veh_$i';
        final reg = 'KA-${(i % 50 + 10).toString().padLeft(2, '0')}-E-${(1000 + i)}';
        final model = 'EV Truck Series ${(i % 5) + 1}';
        final createdIso = now.subtract(const Duration(days: 60)).toIso8601String();
        vehicleSql.write("('$vId', '$reg', '$model', '$createdIso')${i == targetVehicles ? ' ON CONFLICT (id) DO NOTHING;' : ','}");
      }
      await dbService.execute(vehicleSql.toString());

      onProgress?.call(0.10, 'Generating 2,000,000 signal rows in optimized SQL batches...');

      // 2. High-speed multi-row batch inserts for 2 million signal rows (10,000 per batch for low memory overhead)
      const batchSize = 10000;
      int insertedRows = 0;
      final random = Random(12345);

      final signalNames = ['soc', 'range', 'speed', 'battery_temp', 'odometer', 'ignition', 'latitude', 'longitude'];

      while (insertedRows < totalSignalsTarget) {
        final batchSql = StringBuffer(
          'INSERT INTO telemetry_signals (id, vehicle_id, signal_name, value, unit, timestamp, ingested_at) VALUES '
        );

        final countInThisBatch = min(batchSize, totalSignalsTarget - insertedRows);
        for (int b = 0; b < countInThisBatch; b++) {
          final globalIndex = insertedRows + b;
          final vehicleNum = (globalIndex % targetVehicles) + 1;
          final vId = 'veh_$vehicleNum';

          final sigName = signalNames[globalIndex % signalNames.length];
          final val = _generateSignalValue(sigName, random);

          // Spread timestamps over 30 days
          final minutesAgo = (globalIndex / 50).floor();
          final ts = now.subtract(Duration(minutes: minutesAgo));
          final tsIso = ts.toIso8601String();
          final sigId = 's_${runEpoch}_$globalIndex';

          batchSql.write("('$sigId', '$vId', '$sigName', $val, NULL, '$tsIso', '$tsIso')${b == countInThisBatch - 1 ? ' ON CONFLICT (id) DO NOTHING;' : ','}");
        }

        await dbService.execute(batchSql.toString());
        insertedRows += countInThisBatch;

        final progressRatio = 0.10 + (insertedRows / totalSignalsTarget) * 0.75;
        onProgress?.call(
          progressRatio,
          'Inserted ${insertedRows.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} / 2,000,000 signal rows...',
        );
      }

      stopwatch.stop();
      final backfillSeconds = stopwatch.elapsedMilliseconds / 1000.0;

      onProgress?.call(0.90, 'Running fleet query latency benchmarks (100 warm iterations)...');

      // 3. Measure p50 and p95 query latency across 100 iterations
      final latencies = <double>[];
      for (int iter = 0; iter < 100; iter++) {
        final qStopwatch = Stopwatch()..start();
        final rs = await dbService.query('''
          SELECT vehicle_id, reg_number, model, last_ping, soc, range_km, speed, battery_temp, odometer, ignition 
          FROM v_latest_vehicle_status;
        ''');
        rs.fetchAll();
        await rs.dispose();
        qStopwatch.stop();
        latencies.add(qStopwatch.elapsedMicroseconds / 1000.0); // ms
      }

      latencies.sort();
      final p50 = latencies[50];
      final p95 = latencies[95];

      // 4. Memory measurement (Current RSS via ProcessInfo)
      final memoryMb = ProcessInfo.currentRss / (1024 * 1024);

      onProgress?.call(1.0, 'Scale benchmark complete!');

      return BenchmarkReport(
        vehicleCount: targetVehicles,
        totalSignalRows: insertedRows,
        backfillDurationSeconds: backfillSeconds,
        p50QueryLatencyMs: p50,
        p95QueryLatencyMs: p95,
        memoryUsageMb: memoryMb.toDouble(),
      );
    } finally {
      isRunning = false;
    }
  }

  /// Implements Log Compaction & Retention Policy (Section 4)
  /// Prunes raw telemetry signals older than [retentionDays] days while preserving
  /// geofence events, trips, and alert logs intact.
  Future<int> runLogCompaction({int retentionDays = 7}) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays)).toIso8601String();

    final countBefore = await dbService.queryRows('SELECT COUNT(*) FROM telemetry_signals;');
    final initialCount = (countBefore.first.first as num).toInt();

    await dbService.execute('''
      DELETE FROM telemetry_signals 
      WHERE timestamp < '$cutoff';
    ''');

    final countAfter = await dbService.queryRows('SELECT COUNT(*) FROM telemetry_signals;');
    final finalCount = (countAfter.first.first as num).toInt();

    return initialCount - finalCount;
  }

  double _generateSignalValue(String signalName, Random rand) {
    switch (signalName) {
      case 'soc':
        return 15.0 + rand.nextDouble() * 80.0;
      case 'range':
        return 30.0 + rand.nextDouble() * 200.0;
      case 'speed':
        return rand.nextBool() ? 0.0 : (20.0 + rand.nextDouble() * 60.0);
      case 'battery_temp':
        return 25.0 + rand.nextDouble() * 22.0;
      case 'odometer':
        return 5000.0 + rand.nextDouble() * 50000.0;
      case 'ignition':
        return rand.nextBool() ? 1.0 : 0.0;
      case 'latitude':
        return 12.9716 + (rand.nextDouble() - 0.5) * 0.1;
      case 'longitude':
        return 77.5946 + (rand.nextDouble() - 0.5) * 0.1;
      default:
        return 10.0;
    }
  }
}
