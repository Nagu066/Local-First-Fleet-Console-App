class TelemetrySignal {
  final String id;
  final String vehicleId;
  final String signalName;
  final double value;
  final String? unit;
  final DateTime timestamp;
  final DateTime ingestedAt;

  const TelemetrySignal({
    required this.id,
    required this.vehicleId,
    required this.signalName,
    required this.value,
    this.unit,
    required this.timestamp,
    required this.ingestedAt,
  });
}

class TelemetryPacket {
  final String vehicleId;
  final DateTime timestamp;
  final Map<String, double> signals;

  const TelemetryPacket({
    required this.vehicleId,
    required this.timestamp,
    required this.signals,
  });
}
