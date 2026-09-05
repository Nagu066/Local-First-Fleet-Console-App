import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/geofence.dart';
import '../../../core/providers/fleet_providers.dart';

class GeofenceManagementScreen extends ConsumerStatefulWidget {
  const GeofenceManagementScreen({super.key});

  @override
  ConsumerState<GeofenceManagementScreen> createState() => _GeofenceManagementScreenState();
}

class _GeofenceManagementScreenState extends ConsumerState<GeofenceManagementScreen> {
  final Uuid uuid = const Uuid();

  void _showAddEditGeofenceModal({Geofence? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final latCtrl = TextEditingController(text: existing?.centerLat.toString() ?? '12.9716');
    final lngCtrl = TextEditingController(text: existing?.centerLng.toString() ?? '77.5946');
    final radiusCtrl = TextEditingController(text: existing?.radiusMeters.toString() ?? '500.0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          existing == null ? 'Create Persisted Geofence' : 'Edit Geofence',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Geofence Name',
                  labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                ),
              ),
              const SizedBox(height: 8.0),
              TextField(
                controller: latCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Center Latitude',
                  labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                ),
              ),
              const SizedBox(height: 8.0),
              TextField(
                controller: lngCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Center Longitude',
                  labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                ),
              ),
              const SizedBox(height: 8.0),
              TextField(
                controller: radiusCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Radius (Meters)',
                  labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF0F172A),
            ),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final lat = double.tryParse(latCtrl.text.trim()) ?? 12.9716;
              final lng = double.tryParse(lngCtrl.text.trim()) ?? 77.5946;
              final radius = double.tryParse(radiusCtrl.text.trim()) ?? 500.0;

              if (name.isEmpty) return;

              final repo = ref.read(fleetRepositoryProvider);

              if (existing == null) {
                await repo.geofenceEngine.createGeofence(
                  name: name,
                  centerLat: lat,
                  centerLng: lng,
                  radiusMeters: radius,
                  isActive: true,
                );
              } else {
                await repo.geofenceEngine.updateGeofence(
                  id: existing.id,
                  name: name,
                  centerLat: lat,
                  centerLng: lng,
                  radiusMeters: radius,
                  isActive: existing.isActive,
                );
              }

              ref.invalidate(geofencesProvider);
              ref.invalidate(vehicleListProvider);
              if (mounted) Navigator.pop(ctx);
            },
            child: Text(existing == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGeofenceActive(Geofence gf) async {
    final repo = ref.read(fleetRepositoryProvider);
    final newActive = !gf.isActive;

    await repo.geofenceEngine.updateGeofence(
      id: gf.id,
      name: gf.name,
      centerLat: gf.centerLat,
      centerLng: gf.centerLng,
      radiusMeters: gf.radiusMeters,
      isActive: newActive,
    );

    ref.invalidate(geofencesProvider);
    ref.invalidate(vehicleListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final geofencesAsync = ref.watch(geofencesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text('Persisted Circular Geofences'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt, color: Color(0xFF38BDF8)),
            onPressed: () => _showAddEditGeofenceModal(),
          ),
        ],
      ),
      body: geofencesAsync.when(
        data: (geofences) {
          if (geofences.isEmpty) {
            return const Center(
              child: Text('No geofences seeded.', style: TextStyle(color: Color(0xFF94A3B8))),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: geofences.length,
            itemBuilder: (context, index) {
              final gf = geofences[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(
                    color: gf.isActive ? const Color(0xFF38BDF8).withOpacity(0.5) : const Color(0xFF334155),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.bubble_chart,
                                color: gf.isActive ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 8.0),
                              Expanded(
                                child: Text(
                                  gf.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: gf.isActive ? Colors.white : const Color(0xFF94A3B8),
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20.0, color: Color(0xFF38BDF8)),
                              tooltip: 'Edit Geofence',
                              onPressed: () => _showAddEditGeofenceModal(existing: gf),
                            ),
                            Switch(
                              value: gf.isActive,
                              activeColor: const Color(0xFF38BDF8),
                              onChanged: (_) => _toggleGeofenceActive(gf),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Center: (${gf.centerLat.toStringAsFixed(4)}, ${gf.centerLng.toStringAsFixed(4)})',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.0),
                        ),
                        Text(
                          'Radius: ${gf.radiusMeters.toStringAsFixed(0)} m',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13.0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12.0),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.airport_shuttle, size: 16.0, color: Color(0xFF10B981)),
                          const SizedBox(width: 6.0),
                          Text(
                            '${gf.activeVehicleCount} active vehicles inside',
                            style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12.0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
        error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent))),
      ),
    );
  }
}
