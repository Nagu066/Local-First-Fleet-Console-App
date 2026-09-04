enum TripStatus {
  inProgress,
  completed;

  String get label {
    switch (this) {
      case TripStatus.inProgress:
        return 'IN_PROGRESS';
      case TripStatus.completed:
        return 'COMPLETED';
    }
  }

  static TripStatus fromString(String val) {
    if (val.toUpperCase() == 'COMPLETED') return TripStatus.completed;
    return TripStatus.inProgress;
  }
}

class Trip {
  final String id;
  final String vehicleId;
  final String originGeofenceId;
  final String? originGeofenceName;
  final String? destinationGeofenceId;
  final String? destinationGeofenceName;
  final DateTime startTime;
  final DateTime? endTime;
  final TripStatus status;
  final double distanceKm;

  const Trip({
    required this.id,
    required this.vehicleId,
    required this.originGeofenceId,
    this.originGeofenceName,
    this.destinationGeofenceId,
    this.destinationGeofenceName,
    required this.startTime,
    this.endTime,
    required this.status,
    this.distanceKm = 0.0,
  });

  factory Trip.fromRow(List<Object?> row, {String? originName, String? destName}) {
    DateTime parseDateTime(Object? val) {
      if (val is DateTime) return val;
      if (val is String) return DateTime.parse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    return Trip(
      id: row[0].toString(),
      vehicleId: row[1].toString(),
      originGeofenceId: row[2].toString(),
      originGeofenceName: originName,
      destinationGeofenceId: row[3]?.toString(),
      destinationGeofenceName: destName,
      startTime: parseDateTime(row[4]),
      endTime: row[5] != null ? parseDateTime(row[5]) : null,
      status: TripStatus.fromString(row[6].toString()),
      distanceKm: row[7] != null ? (row[7] as num).toDouble() : 0.0,
    );
  }
}
