import 'package:flutter_test/flutter_test.dart';
import 'package:fleet_console/core/engine/verdict_engine.dart';

void main() {
  group('VerdictEngine Tests (Readings Register Verdict Pills)', () {
    final now = DateTime(2026, 9, 4, 12, 0, 0);

    test('Fresh reading within normal threshold produces NORMAL verdict pill', () {
      final freshPing = now.subtract(const Duration(minutes: 2));

      final items = VerdictEngine.evaluateVehicleSignals(
        soc: 85.0,
        rangeKm: 180.0,
        speed: 40.0,
        batteryTemp: 32.0,
        odometer: 15000.0,
        ignition: true,
        lastPing: freshPing,
        referenceTime: now,
      );

      final socItem = items.firstWhere((i) => i.key == 'soc');
      expect(socItem.verdict, equals(SignalVerdict.normal));
      expect(socItem.displayValue, equals('85%'));
      expect(socItem.ageFormatted, equals('2m ago'));

      final tempItem = items.firstWhere((i) => i.key == 'battery_temp');
      expect(tempItem.verdict, equals(SignalVerdict.normal));
    });

    test('Fresh reading outside threshold produces ALERT verdict pill', () {
      final freshPing = now.subtract(const Duration(minutes: 1));

      final items = VerdictEngine.evaluateVehicleSignals(
        soc: 15.0, // < 20% -> ALERT
        rangeKm: 30.0,
        speed: 0.0,
        batteryTemp: 49.5, // > 45 °C -> ALERT
        odometer: 15000.0,
        ignition: true,
        lastPing: freshPing,
        referenceTime: now,
      );

      final socItem = items.firstWhere((i) => i.key == 'soc');
      expect(socItem.verdict, equals(SignalVerdict.alert));

      final tempItem = items.firstWhere((i) => i.key == 'battery_temp');
      expect(tempItem.verdict, equals(SignalVerdict.alert));
    });

    test('Reading older than 15 minutes produces STALE verdict pill', () {
      final oldPing = now.subtract(const Duration(minutes: 20));

      final items = VerdictEngine.evaluateVehicleSignals(
        soc: 15.0, // Even if < 20%, it is STALE because age > 15m!
        rangeKm: 30.0,
        speed: 0.0,
        batteryTemp: 50.0,
        odometer: 15000.0,
        ignition: true,
        lastPing: oldPing,
        referenceTime: now,
      );

      final socItem = items.firstWhere((i) => i.key == 'soc');
      expect(socItem.verdict, equals(SignalVerdict.stale));
      expect(socItem.ageFormatted, equals('20m ago'));
    });

    test('Never reported signal displays "—" with no verdict pill', () {
      final items = VerdictEngine.evaluateVehicleSignals(
        soc: null,
        rangeKm: null,
        speed: null,
        batteryTemp: null,
        odometer: null,
        ignition: null,
        lastPing: null,
        referenceTime: now,
      );

      for (final item in items) {
        expect(item.displayValue, equals('—'));
        expect(item.verdict, isNull);
        expect(item.hasNeverReported, isTrue);
      }
    });
  });
}
