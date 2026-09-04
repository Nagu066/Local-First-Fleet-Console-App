import 'package:flutter_test/flutter_test.dart';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:dart_duckdb/open.dart';
import 'dart:io';
import 'package:fleet_console/core/database/duckdb_service.dart';
import 'package:fleet_console/core/engine/alert_engine.dart';
import 'package:fleet_console/core/models/alert.dart';

void main() {
  late DuckDBService dbService;
  late AlertEngine alertEngine;

  setUpAll(() {
    if (Platform.isMacOS) {
      open.overrideFor(OperatingSystem.macOS, '/opt/homebrew/lib/libduckdb.dylib');
    }
  });

  setUp(() async {
    dbService = DuckDBService();
    await dbService.init(inMemory: true);
    alertEngine = AlertEngine(dbService);

    // Insert dummy vehicle
    await dbService.execute('''
      INSERT INTO vehicles (id, reg_number, model, created_at)
      VALUES ('v100', 'KA-01-E-9999', 'Tata Ace EV', '${DateTime.now().toIso8601String()}');
    ''');
  });

  tearDown(() async {
    await dbService.dispose();
  });

  group('AlertEngine Tests (Escalating Alerts, Dismissal, Undo, Self-Clearing)', () {
    final now = DateTime.now();

    test('SOC < 20% triggers LOW_BATTERY WARNING alert', () async {
      await alertEngine.evaluateTelemetry(
        vehicleId: 'v100',
        soc: 18.0,
        batteryTemp: 30.0,
        timestamp: now,
      );

      final alerts = await alertEngine.fetchActiveAlerts(vehicleId: 'v100');
      expect(alerts.length, equals(1));
      expect(alerts.first.alertType, equals(AlertType.lowBattery));
      expect(alerts.first.severity, equals(AlertSeverity.warning));
    });

    test('Escalates LOW_BATTERY to CRITICAL_BATTERY when SOC drops < 10%', () async {
      // First trigger low battery warning
      await alertEngine.evaluateTelemetry(
        vehicleId: 'v100',
        soc: 18.0,
        batteryTemp: 30.0,
        timestamp: now,
      );

      // Then SOC drops to 8% -> should escalate single alert to critical!
      await alertEngine.evaluateTelemetry(
        vehicleId: 'v100',
        soc: 8.0,
        batteryTemp: 30.0,
        timestamp: now.add(const Duration(minutes: 1)),
      );

      final alerts = await alertEngine.fetchActiveAlerts(vehicleId: 'v100');
      expect(alerts.length, equals(1), reason: 'Must be ONE escalating alert, not two separate alerts');
      expect(alerts.first.alertType, equals(AlertType.criticalBattery));
      expect(alerts.first.severity, equals(AlertSeverity.critical));
    });

    test('Condition clearing: SOC rising >= 20% resolves active alert automatically', () async {
      await alertEngine.evaluateTelemetry(
        vehicleId: 'v100',
        soc: 12.0,
        batteryTemp: 30.0,
        timestamp: now,
      );

      // Verify active alert exists
      var alerts = await alertEngine.fetchActiveAlerts(vehicleId: 'v100');
      expect(alerts.length, equals(1));

      // Telemetry condition clears (SOC recharged to 50%)
      await alertEngine.evaluateTelemetry(
        vehicleId: 'v100',
        soc: 50.0,
        batteryTemp: 30.0,
        timestamp: now.add(const Duration(minutes: 5)),
      );

      alerts = await alertEngine.fetchActiveAlerts(vehicleId: 'v100');
      expect(alerts, isEmpty, reason: 'Alert should automatically resolve when condition clears');
    });

    test('Dismissal and Undo flow', () async {
      await alertEngine.evaluateTelemetry(
        vehicleId: 'v100',
        soc: 15.0,
        batteryTemp: 30.0,
        timestamp: now,
      );

      var alerts = await alertEngine.fetchActiveAlerts(vehicleId: 'v100');
      final alertId = alerts.first.id;

      // User dismisses alert with reason
      await alertEngine.dismissAlert(alertId, 'I am on it');

      alerts = await alertEngine.fetchActiveAlerts(vehicleId: 'v100');
      expect(alerts, isEmpty, reason: 'Dismissed alert must not appear in active list');

      // User taps UNDO within 5s -> restores alert to ACTIVE
      await alertEngine.undoDismissal(alertId);

      alerts = await alertEngine.fetchActiveAlerts(vehicleId: 'v100');
      expect(alerts.length, equals(1));
      expect(alerts.first.status, equals(AlertStatus.active));
    });
  });
}
