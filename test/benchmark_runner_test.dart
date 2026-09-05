import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:dart_duckdb/open.dart';
import 'package:fleet_console/core/database/duckdb_service.dart';
import 'package:fleet_console/features/benchmark/data/scale_generator.dart';

void main() {
  setUpAll(() {
    if (Platform.isMacOS) {
      open.overrideFor(OperatingSystem.macOS, '/opt/homebrew/lib/libduckdb.dylib');
    }
  });

  test('Execute 2 Million Telemetry Benchmark & Measure Metrics', () async {
    final dbService = DuckDBService();
    await dbService.init(inMemory: false, customPath: 'scale_benchmark_meas.duckdb');

    final generator = ScaleGenerator(dbService);
    final report = await generator.runScaleBackfillAndBenchmark(
      onProgress: (progress, status) {
        if ((progress * 100).toInt() % 20 == 0) {
          print('Progress: ${(progress * 100).toStringAsFixed(0)}% - $status');
        }
      },
    );

    print('\n================ SCALE EXERCISE REPORT ================');
    print('Device: Apple Silicon (Mac mini M-series) / iOS Simulator (iPhone 17 Pro)');
    print('Backfill: ${report.vehicleCount} vehicles, ${report.totalSignalRows} signal rows');
    print('Backfill Duration: ${report.backfillDurationSeconds.toStringAsFixed(2)} seconds');
    print('Query Latency p50: ${report.p50QueryLatencyMs.toStringAsFixed(2)} ms');
    print('Query Latency p95: ${report.p95QueryLatencyMs.toStringAsFixed(2)} ms');
    print('Memory at Rest: ${report.memoryUsageMb.toStringAsFixed(1)} MB');
    print('========================================================\n');

    // Clean up measurement db
    await dbService.dispose();
    try {
      final file = File('scale_benchmark_meas.duckdb');
      if (await file.exists()) await file.delete();
      final wal = File('scale_benchmark_meas.duckdb.wal');
      if (await wal.exists()) await wal.delete();
    } catch (_) {}
  }, timeout: const Timeout(Duration(minutes: 5)));
}
