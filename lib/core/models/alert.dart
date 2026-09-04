enum AlertType {
  lowBattery,
  criticalBattery,
  batteryOverheating;

  String get label {
    switch (this) {
      case AlertType.lowBattery:
        return 'Low battery';
      case AlertType.criticalBattery:
        return 'Battery critically low';
      case AlertType.batteryOverheating:
        return 'Battery overheating';
    }
  }

  static AlertType fromString(String val) {
    switch (val.toUpperCase()) {
      case 'LOW_BATTERY':
        return AlertType.lowBattery;
      case 'CRITICAL_BATTERY':
        return AlertType.criticalBattery;
      case 'BATTERY_OVERHEATING':
        return AlertType.batteryOverheating;
      default:
        return AlertType.lowBattery;
    }
  }

  String get dbValue {
    switch (this) {
      case AlertType.lowBattery:
        return 'LOW_BATTERY';
      case AlertType.criticalBattery:
        return 'CRITICAL_BATTERY';
      case AlertType.batteryOverheating:
        return 'BATTERY_OVERHEATING';
    }
  }
}

enum AlertSeverity {
  warning,
  critical;

  String get label {
    switch (this) {
      case AlertSeverity.warning:
        return 'Warning';
      case AlertSeverity.critical:
        return 'Critical';
    }
  }

  static AlertSeverity fromString(String val) {
    if (val.toUpperCase() == 'CRITICAL') return AlertSeverity.critical;
    return AlertSeverity.warning;
  }
}

enum AlertStatus {
  active,
  dismissed,
  resolved;

  static AlertStatus fromString(String val) {
    switch (val.toUpperCase()) {
      case 'DISMISSED':
        return AlertStatus.dismissed;
      case 'RESOLVED':
        return AlertStatus.resolved;
      default:
        return AlertStatus.active;
    }
  }
}

class Alert {
  final String id;
  final String vehicleId;
  final AlertType alertType;
  final AlertSeverity severity;
  final AlertStatus status;
  final String? dismissalReason;
  final DateTime triggeredAt;
  final DateTime updatedAt;
  final DateTime? dismissedAt;
  final DateTime? resolvedAt;

  const Alert({
    required this.id,
    required this.vehicleId,
    required this.alertType,
    required this.severity,
    required this.status,
    this.dismissalReason,
    required this.triggeredAt,
    required this.updatedAt,
    this.dismissedAt,
    this.resolvedAt,
  });

  factory Alert.fromRow(List<Object?> row) {
    DateTime parseDateTime(Object? val) {
      if (val is DateTime) return val;
      if (val is String) return DateTime.parse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    return Alert(
      id: row[0].toString(),
      vehicleId: row[1].toString(),
      alertType: AlertType.fromString(row[2].toString()),
      severity: AlertSeverity.fromString(row[3].toString()),
      status: AlertStatus.fromString(row[4].toString()),
      dismissalReason: row[5]?.toString(),
      triggeredAt: parseDateTime(row[6]),
      updatedAt: parseDateTime(row[7]),
      dismissedAt: row[8] != null ? parseDateTime(row[8]) : null,
      resolvedAt: row[9] != null ? parseDateTime(row[9]) : null,
    );
  }
}
