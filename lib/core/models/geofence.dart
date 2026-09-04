class Geofence {
  final String id;
  final String name;
  final double centerLat;
  final double centerLng;
  final double radiusMeters;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int activeVehicleCount;

  const Geofence({
    required this.id,
    required this.name,
    required this.centerLat,
    required this.centerLng,
    required this.radiusMeters,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.activeVehicleCount = 0,
  });

  Geofence copyWith({
    String? id,
    String? name,
    double? centerLat,
    double? centerLng,
    double? radiusMeters,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? activeVehicleCount,
  }) {
    return Geofence(
      id: id ?? this.id,
      name: name ?? this.name,
      centerLat: centerLat ?? this.centerLat,
      centerLng: centerLng ?? this.centerLng,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      activeVehicleCount: activeVehicleCount ?? this.activeVehicleCount,
    );
  }

  factory Geofence.fromRow(List<Object?> row, {int activeVehicleCount = 0}) {
    DateTime parseDateTime(Object? val) {
      if (val is DateTime) return val;
      if (val is String) return DateTime.parse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    return Geofence(
      id: row[0].toString(),
      name: row[1].toString(),
      centerLat: (row[2] as num).toDouble(),
      centerLng: (row[3] as num).toDouble(),
      radiusMeters: (row[4] as num).toDouble(),
      isActive: row[5] == true || row[5] == 1 || row[5] == 'true',
      createdAt: parseDateTime(row[6]),
      updatedAt: parseDateTime(row[7]),
      activeVehicleCount: activeVehicleCount,
    );
  }
}

enum GeofenceEventType {
  entry,
  exit;

  String get label {
    switch (this) {
      case GeofenceEventType.entry:
        return 'ENTRY';
      case GeofenceEventType.exit:
        return 'EXIT';
    }
  }
}

class GeofenceEvent {
  final String id;
  final String vehicleId;
  final String geofenceId;
  final GeofenceEventType eventType;
  final DateTime timestamp;

  const GeofenceEvent({
    required this.id,
    required this.vehicleId,
    required this.geofenceId,
    required this.eventType,
    required this.timestamp,
  });
}
