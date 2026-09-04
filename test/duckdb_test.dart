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

  test('DuckDB basic query test', () async {
    final db = await duckdb.open(':memory:');
    final conn = await duckdb.connect(db);
    
    await conn.execute("CREATE TABLE test (id INT, name VARCHAR);");
    await conn.execute("INSERT INTO test VALUES (1, 'Truck A'), (2, 'Truck B');");
    
    final result = await conn.query("SELECT * FROM test;");
    expect(result.rowCount, equals(2));
    expect(result.columnNames, equals(['id', 'name']));
    
    final rows = result.fetchAll();
    print('Fetched rows: $rows');
    expect(rows.length, equals(2));
    expect(rows[0], equals([1, 'Truck A']));
    expect(rows[1], equals([2, 'Truck B']));
    
    await result.dispose();
    await conn.dispose();
    await db.dispose();
  });
}
