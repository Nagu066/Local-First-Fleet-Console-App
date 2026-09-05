import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:dart_duckdb/open.dart';
import 'package:fleet_console/core/database/duckdb_service.dart';

void main() {
  late DuckDBService dbService;

  setUpAll(() async {
    if (Platform.isMacOS) {
      open.overrideFor(OperatingSystem.macOS, '/opt/homebrew/lib/libduckdb.dylib');
    }
    dbService = DuckDBService();
    await dbService.init(inMemory: true);
  });

  tearDownAll(() async {
    await dbService.dispose();
  });

  test('Downsamples 2000 SOC records down to ~60 clean spots', () async {
    final now = DateTime.now();
    // Insert 2000 records
    for (int b = 0; b < 20; b++) {
      final buffer = StringBuffer('INSERT INTO telemetry_signals (id, vehicle_id, signal_name, value, unit, timestamp, ingested_at) VALUES ');
      for (int i = 0; i < 100; i++) {
        final idx = b * 100 + i;
        final ts = now.subtract(Duration(minutes: 2000 - idx)).toIso8601String();
        final val = 50.0 + (idx % 30);
        buffer.write("('sig_$idx', 'veh_1', 'soc', $val, '%', '$ts', '$ts')${i == 99 ? ';' : ','}");
      }
      await dbService.execute(buffer.toString());
    }

    final countRes = await dbService.queryRows('''
      SELECT COUNT(*) FROM telemetry_signals 
      WHERE vehicle_id = 'veh_1' AND signal_name = 'soc';
    ''');
    final totalCount = (countRes.first[0] as num).toInt();
    expect(totalCount, equals(2000));

    final step = (totalCount / 60.0).ceil();
    final rows = await dbService.queryRows('''
      WITH numbered AS (
        SELECT 
          timestamp, 
          value,
          ROW_NUMBER() OVER (ORDER BY timestamp ASC) AS rn
        FROM telemetry_signals
        WHERE vehicle_id = 'veh_1' AND signal_name = 'soc'
      )
      SELECT timestamp, value
      FROM numbered
      WHERE (rn % $step = 0) OR rn = $totalCount
      ORDER BY timestamp ASC;
    ''');

    expect(rows.length, inInclusiveRange(50, 65));
    expect((rows.first[1] as num).toDouble(), isNotNull);
    expect((rows.last[1] as num).toDouble(), isNotNull);
  });
}
