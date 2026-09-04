import 'package:intl/intl.dart';

enum SignalVerdict {
  normal,
  alert,
  stale;

  String get label {
    switch (this) {
      case SignalVerdict.normal:
        return 'NORMAL';
      case SignalVerdict.alert:
        return 'ALERT';
      case SignalVerdict.stale:
        return 'STALE';
    }
  }
}

class SignalReadingItem {
  final String key;
  final String label;
  final String displayValue;
  final String? unit;
  final DateTime? timestamp;
  final String ageFormatted;
  final SignalVerdict? verdict;
  final bool hasNeverReported;

  const SignalReadingItem({
    required this.key,
    required this.label,
    required this.displayValue,
    this.unit,
    this.timestamp,
    required this.ageFormatted,
    this.verdict,
    this.hasNeverReported = false,
  });
}

class VerdictEngine {
  /// Freshness threshold duration (15 minutes). Telemetry older than 15 mins is marked STALE.
  static const Duration freshnessWindow = Duration(minutes: 15);

  static List<SignalReadingItem> evaluateVehicleSignals({
    required double? soc,
    required double? rangeKm,
    required double? speed,
    required double? batteryTemp,
    required double? odometer,
    required bool? ignition,
    required DateTime? lastPing,
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();

    SignalReadingItem buildItem({
      required String key,
      required String label,
      required double? numValue,
      required String displayValue,
      required String? unit,
      required DateTime? signalTime,
      required SignalVerdict? Function(double val)? alertChecker,
    }) {
      if (numValue == null || signalTime == null) {
        return SignalReadingItem(
          key: key,
          label: label,
          displayValue: '—',
          unit: unit,
          timestamp: null,
          ageFormatted: 'Never',
          verdict: null,
          hasNeverReported: true,
        );
      }

      final ageSec = now.difference(signalTime).inSeconds;
      final ageStr = _formatAge(ageSec);

      if (ageSec > freshnessWindow.inSeconds) {
        // STALE: grey pill, no normal or alert claim
        return SignalReadingItem(
          key: key,
          label: label,
          displayValue: displayValue,
          unit: unit,
          timestamp: signalTime,
          ageFormatted: ageStr,
          verdict: SignalVerdict.stale,
        );
      }

      // Fresh reading: evaluate threshold
      final verdict = (alertChecker != null) ? (alertChecker(numValue) ?? SignalVerdict.normal) : SignalVerdict.normal;

      return SignalReadingItem(
        key: key,
        label: label,
        displayValue: displayValue,
        unit: unit,
        timestamp: signalTime,
        ageFormatted: ageStr,
        verdict: verdict,
      );
    }

    return [
      buildItem(
        key: 'soc',
        label: 'State of Charge (SOC)',
        numValue: soc,
        displayValue: soc != null ? '${soc.toStringAsFixed(0)}%' : '—',
        unit: '%',
        signalTime: lastPing,
        alertChecker: (val) => val < 20.0 ? SignalVerdict.alert : SignalVerdict.normal,
      ),
      buildItem(
        key: 'range',
        label: 'Estimated Range',
        numValue: rangeKm,
        displayValue: rangeKm != null ? '${rangeKm.toStringAsFixed(1)} km' : '—',
        unit: 'km',
        signalTime: lastPing,
        alertChecker: (_) => SignalVerdict.normal,
      ),
      buildItem(
        key: 'speed',
        label: 'Current Speed',
        numValue: speed,
        displayValue: speed != null ? '${speed.toStringAsFixed(1)} km/h' : '—',
        unit: 'km/h',
        signalTime: lastPing,
        alertChecker: (_) => SignalVerdict.normal,
      ),
      buildItem(
        key: 'battery_temp',
        label: 'Battery Temperature',
        numValue: batteryTemp,
        displayValue: batteryTemp != null ? '${batteryTemp.toStringAsFixed(1)} °C' : '—',
        unit: '°C',
        signalTime: lastPing,
        alertChecker: (val) => val > 45.0 ? SignalVerdict.alert : SignalVerdict.normal,
      ),
      buildItem(
        key: 'odometer',
        label: 'Odometer',
        numValue: odometer,
        displayValue: odometer != null ? '${NumberFormat('#,##0.0').format(odometer)} km' : '—',
        unit: 'km',
        signalTime: lastPing,
        alertChecker: (_) => SignalVerdict.normal,
      ),
      buildItem(
        key: 'ignition',
        label: 'Ignition State',
        numValue: ignition != null ? (ignition ? 1.0 : 0.0) : null,
        displayValue: ignition != null ? (ignition ? 'ON' : 'OFF') : '—',
        unit: null,
        signalTime: lastPing,
        alertChecker: (_) => SignalVerdict.normal,
      ),
      buildItem(
        key: 'last_ping',
        label: 'Last Telemetry Ping',
        numValue: lastPing != null ? 1.0 : null,
        displayValue: lastPing != null ? DateFormat('HH:mm:ss').format(lastPing) : '—',
        unit: null,
        signalTime: lastPing,
        alertChecker: (_) => SignalVerdict.normal,
      ),
    ];
  }

  static String _formatAge(int seconds) {
    if (seconds < 0) return '0s ago';
    if (seconds < 60) return '${seconds}s ago';
    if (seconds < 3600) return '${(seconds / 60).floor()}m ago';
    if (seconds < 86400) return '${(seconds / 3600).floor()}h ago';
    return '${(seconds / 86400).floor()}d ago';
  }
}
