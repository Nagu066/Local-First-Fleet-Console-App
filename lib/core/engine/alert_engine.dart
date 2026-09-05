import 'package:uuid/uuid.dart';
import '../database/duckdb_service.dart';
import '../models/alert.dart';

class AlertEngine {
  final DuckDBService dbService;
  final Uuid uuid = const Uuid();

  AlertEngine(this.dbService);

  /// Evaluates telemetry values for a vehicle and updates active/resolved/escalated alerts in DuckDB.
  /// Enforces Section 3.C requirement: "Thresholds, on fresh readings only" (within 15 minutes of current clock).
  Future<void> evaluateTelemetry({
    required String vehicleId,
    required double? soc,
    required double? batteryTemp,
    required DateTime timestamp,
    DateTime? currentClock,
  }) async {
    final now = currentClock ?? DateTime.now();
    final nowIso = DateTime.now().toIso8601String();

    // Check reading freshness: fresh if event time is within 15 minutes of clock
    final isFresh = now.difference(timestamp).inMinutes.abs() <= 15;

    // 1. Evaluate SOC Alert (Escalating: LOW_BATTERY < 20%, CRITICAL_BATTERY < 10%)
    if (soc != null) {
      await _evaluateSocAlert(
        vehicleId: vehicleId,
        soc: soc,
        timestamp: timestamp,
        nowIso: nowIso,
        isFresh: isFresh,
      );
    }

    // 2. Evaluate Battery Overheating Alert (> 45 °C)
    if (batteryTemp != null) {
      await _evaluateOverheatingAlert(
        vehicleId: vehicleId,
        batteryTemp: batteryTemp,
        timestamp: timestamp,
        nowIso: nowIso,
        isFresh: isFresh,
      );
    }
  }

  Future<void> _evaluateSocAlert({
    required String vehicleId,
    required double soc,
    required DateTime timestamp,
    required String nowIso,
    required bool isFresh,
  }) async {
    // Check for existing active or dismissed SOC alert for this vehicle
    final existingRows = await dbService.queryRows('''
      SELECT id, alert_type, severity, status 
      FROM alerts 
      WHERE vehicle_id = '$vehicleId' 
        AND alert_type IN ('LOW_BATTERY', 'CRITICAL_BATTERY') 
        AND status IN ('ACTIVE', 'DISMISSED')
      LIMIT 1;
    ''');

    if (soc >= 20.0) {
      // Condition cleared: resolve existing alert if any (resolves independently of dismissal)
      if (existingRows.isNotEmpty) {
        final alertId = existingRows[0][0].toString();
        await dbService.execute('''
          UPDATE alerts 
          SET status = 'RESOLVED', resolved_at = '$nowIso', updated_at = '$nowIso' 
          WHERE id = '$alertId';
        ''');
      }
    } else if (soc < 10.0) {
      // Critical level (< 10%) - triggers/escalates on fresh readings only
      if (!isFresh) return;

      if (existingRows.isEmpty) {
        // Trigger new critical alert
        final newId = uuid.v4();
        final tsIso = timestamp.toIso8601String();
        await dbService.execute('''
          INSERT INTO alerts (id, vehicle_id, alert_type, severity, status, triggered_at, updated_at)
          VALUES ('$newId', '$vehicleId', 'CRITICAL_BATTERY', 'CRITICAL', 'ACTIVE', '$tsIso', '$nowIso');
        ''');
      } else {
        // Escalate existing warning alert if needed
        final alertId = existingRows[0][0].toString();
        final currentType = existingRows[0][1].toString();
        if (currentType != 'CRITICAL_BATTERY') {
          await dbService.execute('''
            UPDATE alerts 
            SET alert_type = 'CRITICAL_BATTERY', severity = 'CRITICAL', status = 'ACTIVE', updated_at = '$nowIso' 
            WHERE id = '$alertId';
          ''');
        }
      }
    } else {
      // Warning level (10% <= SOC < 20%) - triggers on fresh readings only
      if (!isFresh) return;

      if (existingRows.isEmpty) {
        // Trigger new low battery alert
        final newId = uuid.v4();
        final tsIso = timestamp.toIso8601String();
        await dbService.execute('''
          INSERT INTO alerts (id, vehicle_id, alert_type, severity, status, triggered_at, updated_at)
          VALUES ('$newId', '$vehicleId', 'LOW_BATTERY', 'WARNING', 'ACTIVE', '$tsIso', '$nowIso');
        ''');
      } else {
        // De-escalate from critical to warning if needed
        final alertId = existingRows[0][0].toString();
        final currentType = existingRows[0][1].toString();
        if (currentType == 'CRITICAL_BATTERY') {
          await dbService.execute('''
            UPDATE alerts 
            SET alert_type = 'LOW_BATTERY', severity = 'WARNING', updated_at = '$nowIso' 
            WHERE id = '$alertId';
          ''');
        }
      }
    }
  }

  Future<void> _evaluateOverheatingAlert({
    required String vehicleId,
    required double batteryTemp,
    required DateTime timestamp,
    required String nowIso,
    required bool isFresh,
  }) async {
    final existingRows = await dbService.queryRows('''
      SELECT id, status 
      FROM alerts 
      WHERE vehicle_id = '$vehicleId' 
        AND alert_type = 'BATTERY_OVERHEATING' 
        AND status IN ('ACTIVE', 'DISMISSED')
      LIMIT 1;
    ''');

    if (batteryTemp > 45.0) {
      // Overheating threshold (> 45°C) - triggers on fresh readings only
      if (!isFresh) return;

      if (existingRows.isEmpty) {
        final newId = uuid.v4();
        final tsIso = timestamp.toIso8601String();
        await dbService.execute('''
          INSERT INTO alerts (id, vehicle_id, alert_type, severity, status, triggered_at, updated_at)
          VALUES ('$newId', '$vehicleId', 'BATTERY_OVERHEATING', 'CRITICAL', 'ACTIVE', '$tsIso', '$nowIso');
        ''');
      }
    } else {
      // Temp <= 45°C -> resolve overheating alert if active
      if (existingRows.isNotEmpty) {
        final alertId = existingRows[0][0].toString();
        await dbService.execute('''
          UPDATE alerts 
          SET status = 'RESOLVED', resolved_at = '$nowIso', updated_at = '$nowIso' 
          WHERE id = '$alertId';
        ''');
      }
    }
  }

  /// Dismisses an alert with user reason ("I am on it", "Wrong alert", "Something else…")
  Future<void> dismissAlert(String alertId, String reason) async {
    final nowIso = DateTime.now().toIso8601String();
    final sanitizedReason = reason.replaceAll("'", "''");
    await dbService.execute('''
      UPDATE alerts 
      SET status = 'DISMISSED', dismissal_reason = '$sanitizedReason', dismissed_at = '$nowIso', updated_at = '$nowIso' 
      WHERE id = '$alertId';
    ''');
  }

  /// Restores a dismissed alert back to ACTIVE status (UNDO flow)
  Future<void> undoDismissal(String alertId) async {
    final nowIso = DateTime.now().toIso8601String();
    await dbService.execute('''
      UPDATE alerts 
      SET status = 'ACTIVE', dismissal_reason = NULL, dismissed_at = NULL, updated_at = '$nowIso' 
      WHERE id = '$alertId';
    ''');
  }

  /// Queries all active alerts for fleet
  Future<List<Alert>> fetchActiveAlerts({String? vehicleId}) async {
    final whereClause = vehicleId != null
        ? "WHERE status = 'ACTIVE' AND vehicle_id = '$vehicleId'"
        : "WHERE status = 'ACTIVE'";

    final rows = await dbService.queryRows('''
      SELECT id, vehicle_id, alert_type, severity, status, dismissal_reason, triggered_at, updated_at, dismissed_at, resolved_at 
      FROM alerts 
      $whereClause
      ORDER BY triggered_at DESC;
    ''');

    return rows.map((r) => Alert.fromRow(r)).toList();
  }
}
