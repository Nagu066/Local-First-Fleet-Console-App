enum VehicleStatus {
  offline,
  moving,
  idle,
  stopped;

  String get label {
    switch (this) {
      case VehicleStatus.offline:
        return 'OFFLINE';
      case VehicleStatus.moving:
        return 'MOVING';
      case VehicleStatus.idle:
        return 'IDLE';
      case VehicleStatus.stopped:
        return 'STOPPED';
    }
  }
}

class Vehicle {
  final String id;
  final String regNumber;
  final String model;
  final DateTime? lastPing;
  final double? soc;
  final double? rangeKm;
  final double? speed;
  final double? batteryTemp;
  final double? odometer;
  final bool? ignition;
  final double? latitude;
  final double? longitude;
  final bool hasActiveAlert;
  final String? currentGeofenceName;

  const Vehicle({
    required this.id,
    required this.regNumber,
    required this.model,
    this.lastPing,
    this.soc,
    this.rangeKm,
    this.speed,
    this.batteryTemp,
    this.odometer,
    this.ignition,
    this.latitude,
    this.longitude,
    this.hasActiveAlert = false,
    this.currentGeofenceName,
  });

  /// Computes vehicle status using "first match wins" rule:
  /// 1. OFFLINE: last ping older than 10 minutes (or never reported)
  /// 2. MOVING: speed > 0
  /// 3. IDLE: speed == 0 AND ignition is on
  /// 4. STOPPED: ignition is off
  VehicleStatus calculateStatus({DateTime? referenceTime}) {
    final now = referenceTime ?? DateTime.now();

    if (lastPing == null || now.difference(lastPing!).inSeconds > 600) {
      return VehicleStatus.offline;
    }

    final currentSpeed = speed ?? 0.0;
    if (currentSpeed > 0) {
      return VehicleStatus.moving;
    }

    final isIgnitionOn = ignition ?? false;
    if (currentSpeed == 0 && isIgnitionOn) {
      return VehicleStatus.idle;
    }

    return VehicleStatus.stopped;
  }

  factory Vehicle.fromRow(List<Object?> row, {bool hasActiveAlert = false, String? currentGeofenceName}) {
    DateTime? parseDateTime(Object? val) {
      if (val == null) return null;
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    double? parseDouble(Object? val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }

    bool? parseBool(Object? val) {
      if (val == null) return null;
      if (val is bool) return val;
      if (val is num) return val != 0;
      if (val is String) return val == 'true' || val == '1';
      return null;
    }

    String? parseGeofence(Object? val) {
      if (val == null) return null;
      final str = val.toString().trim();
      return str.isEmpty ? null : str;
    }

    return Vehicle(
      id: row[0].toString(),
      regNumber: row[1].toString(),
      model: row[2].toString(),
      lastPing: parseDateTime(row[3]),
      soc: parseDouble(row[4]),
      rangeKm: parseDouble(row[5]),
      speed: parseDouble(row[6]),
      batteryTemp: parseDouble(row[7]),
      odometer: parseDouble(row[8]),
      ignition: parseBool(row[9]),
      latitude: parseDouble(row[10]),
      longitude: parseDouble(row[11]),
      hasActiveAlert: hasActiveAlert,
      currentGeofenceName: currentGeofenceName ?? (row.length > 13 ? parseGeofence(row[13]) : null),
    );
  }
}
