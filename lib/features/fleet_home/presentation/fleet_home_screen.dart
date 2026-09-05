import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/fleet_providers.dart';
import 'widgets/vehicle_card.dart';
import '../../vehicle_detail/presentation/vehicle_detail_screen.dart';
import '../../geofences/presentation/geofence_management_screen.dart';
import '../../benchmark/presentation/benchmark_screen.dart';

class FleetHomeScreen extends ConsumerStatefulWidget {
  const FleetHomeScreen({super.key});

  @override
  ConsumerState<FleetHomeScreen> createState() => _FleetHomeScreenState();
}

class _FleetHomeScreenState extends ConsumerState<FleetHomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicleListAsync = ref.watch(vehicleListProvider);
    final statusCountsAsync = ref.watch(fleetStatusCountsProvider);
    final currentFilter = ref.watch(selectedStatusFilterProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark Navy/Slate
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFF38BDF8)),
            SizedBox(width: 8.0),
            Text(
              'Fleet Console',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF38BDF8),
                backgroundColor: const Color(0xFF0F172A),
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  side: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
              icon: const Icon(Icons.fmd_good, size: 16.0, color: Color(0xFF38BDF8)),
              label: const Text('Geofences', style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GeofenceManagementScreen()),
                );
              },
            ),
          ),
          const SizedBox(width: 4.0),
          IconButton(
            icon: const Icon(Icons.speed, color: Color(0xFFF59E0B)),
            tooltip: 'Scale Benchmark',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BenchmarkScreen()),
              );
            },
          ),
          const SizedBox(width: 8.0),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final repo = ref.read(fleetRepositoryProvider);
          await repo.seedInitialDataIfEmpty();
          ref.invalidate(vehicleListProvider);
          ref.invalidate(fleetStatusCountsProvider);
          ref.invalidate(geofencesProvider);
        },
        child: Column(
          children: [
            // Search Bar & Filter Chips Section
            Container(
              color: const Color(0xFF1E293B),
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      ref.read(searchQueryProvider.notifier).state = val;
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search reg number or model...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Color(0xFF64748B)),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(searchQueryProvider.notifier).state = '';
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  // Filter Chips
                  statusCountsAsync.when(
                    data: (counts) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              label: 'ALL',
                              count: counts.allCount,
                              isSelected: currentFilter == 'ALL',
                              onTap: () => ref.read(selectedStatusFilterProvider.notifier).state = 'ALL',
                            ),
                            _buildFilterChip(
                              label: 'MOVING',
                              count: counts.movingCount,
                              isSelected: currentFilter == 'MOVING',
                              color: const Color(0xFF10B981),
                              onTap: () => ref.read(selectedStatusFilterProvider.notifier).state = 'MOVING',
                            ),
                            _buildFilterChip(
                              label: 'IDLE',
                              count: counts.idleCount,
                              isSelected: currentFilter == 'IDLE',
                              color: const Color(0xFFF59E0B),
                              onTap: () => ref.read(selectedStatusFilterProvider.notifier).state = 'IDLE',
                            ),
                            _buildFilterChip(
                              label: 'STOPPED',
                              count: counts.stoppedCount,
                              isSelected: currentFilter == 'STOPPED',
                              color: const Color(0xFFEF4444),
                              onTap: () => ref.read(selectedStatusFilterProvider.notifier).state = 'STOPPED',
                            ),
                            _buildFilterChip(
                              label: 'OFFLINE',
                              count: counts.offlineCount,
                              isSelected: currentFilter == 'OFFLINE',
                              color: const Color(0xFF64748B),
                              onTap: () => ref.read(selectedStatusFilterProvider.notifier).state = 'OFFLINE',
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox(height: 36.0),
                    error: (_, __) => const SizedBox(),
                  ),
                ],
              ),
            ),

            // Vehicle List
            Expanded(
              child: vehicleListAsync.when(
                data: (vehicles) {
                  if (vehicles.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_car_outlined,
                            size: 64.0,
                            color: const Color(0xFF334155),
                          ),
                          const SizedBox(height: 16.0),
                          const Text(
                            'No vehicles match filter criteria',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 16.0,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF38BDF8),
                              foregroundColor: const Color(0xFF0F172A),
                            ),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(searchQueryProvider.notifier).state = '';
                              ref.read(selectedStatusFilterProvider.notifier).state = 'ALL';
                            },
                            child: const Text('Reset Filters'),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    itemCount: vehicles.length,
                    itemBuilder: (context, index) {
                      final vehicle = vehicles[index];
                      return VehicleCard(
                        vehicle: vehicle,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VehicleDetailScreen(vehicleId: vehicle.id),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
                ),
                error: (err, stack) => Center(
                  child: Text(
                    'Error querying DuckDB: $err',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required int count,
    required bool isSelected,
    Color color = const Color(0xFF38BDF8),
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.25) : const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: isSelected ? color : const Color(0xFF334155),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 12.0,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6.0),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: isSelected ? color : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                    fontSize: 11.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
