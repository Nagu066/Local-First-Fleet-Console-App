import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/duckdb_service.dart';
import '../../features/fleet_home/data/fleet_repository.dart';
import '../../features/benchmark/data/scale_generator.dart';
import '../models/vehicle.dart';
import '../models/geofence.dart';
import '../models/alert.dart';
import '../models/trip.dart';

final duckDBServiceProvider = Provider<DuckDBService>((ref) {
  return DuckDBService();
});

final fleetRepositoryProvider = Provider<FleetRepository>((ref) {
  final dbService = ref.watch(duckDBServiceProvider);
  return FleetRepository(dbService);
});

final selectedStatusFilterProvider = StateProvider<String>((ref) => 'ALL');

final searchQueryProvider = StateProvider<String>((ref) => '');

final fleetStatusCountsProvider = FutureProvider<FleetStatusCounts>((ref) async {
  final repo = ref.watch(fleetRepositoryProvider);
  return await repo.fetchStatusCounts();
});

final vehicleListProvider = FutureProvider<List<Vehicle>>((ref) async {
  final repo = ref.watch(fleetRepositoryProvider);
  final filter = ref.watch(selectedStatusFilterProvider);
  final query = ref.watch(searchQueryProvider);
  return await repo.fetchFleetList(statusFilter: filter, searchQuery: query);
});

final vehicleDetailProvider = FutureProvider.family<Vehicle?, String>((ref, vehicleId) async {
  final repo = ref.watch(fleetRepositoryProvider);
  final list = await repo.fetchFleetList(statusFilter: 'ALL');
  return list.firstWhere((v) => v.id == vehicleId, orElse: () => list.first);
});

final geofencesProvider = FutureProvider<List<Geofence>>((ref) async {
  final repo = ref.watch(fleetRepositoryProvider);
  return await repo.geofenceEngine.fetchAllGeofences();
});

final vehicleTripsProvider = FutureProvider.family<List<Trip>, String>((ref, vehicleId) async {
  final repo = ref.watch(fleetRepositoryProvider);
  return await repo.tripEngine.fetchVehicleTrips(vehicleId);
});

final activeAlertsProvider = FutureProvider.family<List<Alert>, String?>((ref, vehicleId) async {
  final repo = ref.watch(fleetRepositoryProvider);
  return await repo.alertEngine.fetchActiveAlerts(vehicleId: vehicleId);
});

final benchmarkProgressProvider = StateProvider<double>((ref) => 0.0);
final benchmarkStatusProvider = StateProvider<String>((ref) => 'Ready to execute 2M+ telemetry scale benchmark');
final benchmarkReportProvider = StateProvider<BenchmarkReport?>((ref) => null);
final isBenchmarkRunningProvider = StateProvider<bool>((ref) => false);
