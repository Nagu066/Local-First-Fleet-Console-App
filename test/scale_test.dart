import 'package:flutter_test/flutter_test.dart';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:dart_duckdb/open.dart';
import 'dart:io';

void main() {
  setUpAll(() {
    if (Platform.isMacOS) {
      open.overrideFor(OperatingSystem.macOS, '/opt/homebrew/lib/libduckdb.dylib');
    }
  });

  test('DuckDB high speed batch with ON CONFLICT DO NOTHING', () async {
    final db = await duckdb.open(':memory:');
    final conn = await duckdb.connect(db);

    await conn.execute('''
      CREATE TABLE telemetry_signals (
        id VARCHAR PRIMARY KEY,
        vehicle_id VARCHAR NOT NULL,
        signal_name VARCHAR NOT NULL,
        value DOUBLE NOT NULL,
        unit VARCHAR,
        timestamp TIMESTAMP NOT NULL,
        ingested_at TIMESTAMP NOT NULL
      );
    ''');

    final sw = Stopwatch()..start();
    const batchSize = 5000;
    const total = 50000;

    for (int i = 0; i < total; i += batchSize) {
      final sb = StringBuffer(
        'INSERT INTO telemetry_signals (id, vehicle_id, signal_name, value, unit, timestamp, ingested_at) VALUES '
      );
      for (int b = 0; b < batchSize; b++) {
        final idx = i + b;
        sb.write("('sig_$idx', 'veh_1', 'soc', 50.0, NULL, '2026-09-04 12:00:00', '2026-09-04 12:00:00')");
        sb.write(b == batchSize - 1 ? ' ON CONFLICT (id) DO NOTHING;' : ',');
      }
      await conn.execute(sb.toString());
    }
    sw.stop();
    print('Inserted $total rows in ${sw.elapsedMilliseconds}ms');

    final countRes = await conn.query('SELECT COUNT(*) FROM telemetry_signals;');
    final count = countRes.fetchAll()[0][0];
    expect(count, equals(total));

    // Try inserting again - should NOT throw constraint error!
    final sb = StringBuffer(
      'INSERT INTO telemetry_signals (id, vehicle_id, signal_name, value, unit, timestamp, ingested_at) VALUES '
    );
    sb.write("('sig_0', 'veh_1', 'soc', 50.0, NULL, '2026-09-04 12:00:00', '2026-09-04 12:00:00') ON CONFLICT (id) DO NOTHING;");
    await conn.execute(sb.toString());

    await countRes.dispose();
    await conn.dispose();
    await db.dispose();
  });
}
