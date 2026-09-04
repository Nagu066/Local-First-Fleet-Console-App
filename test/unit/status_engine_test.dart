import 'package:flutter_test/flutter_test.dart';
import 'package:fleet_console/core/models/vehicle.dart';

void main() {
  group('Vehicle Status Rule Engine (First Match Wins)', () {
    final now = DateTime(2026, 9, 4, 12, 0, 0);

    test('OFFLINE: when last ping is older than 10 minutes (600 seconds)', () {
      final oldPing = now.subtract(const Duration(minutes: 11));
      final vehicle = Vehicle(
        id: 'v1',
        regNumber: 'KA-01-E-1001',
        model: 'Tata Ace EV',
        lastPing: oldPing,
        speed: 50.0, // Even if speed > 0, OFFLINE wins because ping is stale!
        ignition: true,
      );

      expect(vehicle.calculateStatus(referenceTime: now), equals(VehicleStatus.offline));
    });

    test('OFFLINE: when vehicle has never sent a ping (lastPing is null)', () {
      const vehicle = Vehicle(
        id: 'v2',
        regNumber: 'KA-01-E-1002',
        model: 'Mahindra Treo',
        lastPing: null,
      );

      expect(vehicle.calculateStatus(referenceTime: now), equals(VehicleStatus.offline));
    });

    test('MOVING: when last ping is fresh and speed > 0', () {
      final freshPing = now.subtract(const Duration(minutes: 2));
      final vehicle = Vehicle(
        id: 'v3',
        regNumber: 'KA-01-E-1003',
        model: 'Ashok Leyland EV',
        lastPing: freshPing,
        speed: 35.5,
        ignition: true,
      );

      expect(vehicle.calculateStatus(referenceTime: now), equals(VehicleStatus.moving));
    });

    test('IDLE: when speed == 0 and ignition is ON', () {
      final freshPing = now.subtract(const Duration(minutes: 1));
      final vehicle = Vehicle(
        id: 'v4',
        regNumber: 'KA-01-E-1004',
        model: 'Eicher EV',
        lastPing: freshPing,
        speed: 0.0,
        ignition: true,
      );

      expect(vehicle.calculateStatus(referenceTime: now), equals(VehicleStatus.idle));
    });

    test('STOPPED: when ignition is OFF', () {
      final freshPing = now.subtract(const Duration(minutes: 3));
      final vehicle = Vehicle(
        id: 'v5',
        regNumber: 'KA-01-E-1005',
        model: 'BYD T3',
        lastPing: freshPing,
        speed: 0.0,
        ignition: false,
      );

      expect(vehicle.calculateStatus(referenceTime: now), equals(VehicleStatus.stopped));
    });
  });
}
