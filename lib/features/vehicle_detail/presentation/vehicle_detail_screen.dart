import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/models/vehicle.dart';
import '../../../core/models/alert.dart';
import '../../../core/models/trip.dart';
import '../../../core/engine/verdict_engine.dart';
import '../../../core/providers/fleet_providers.dart';
import '../../fleet_home/presentation/widgets/status_chip.dart';
import 'widgets/verdict_pill.dart';
import '../../alerts/presentation/widgets/reason_sheet_modal.dart';

class VehicleDetailScreen extends ConsumerStatefulWidget {
  final String vehicleId;

  const VehicleDetailScreen({super.key, required this.vehicleId});

  @override
  ConsumerState<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends ConsumerState<VehicleDetailScreen> {
  List<FlSpot> _socHistorySpots = [];
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadSocHistory();
  }

  Future<void> _loadSocHistory() async {
    final dbService = ref.read(duckDBServiceProvider);
    try {
      final rows = await dbService.queryRows('''
        SELECT timestamp, value 
        FROM telemetry_signals 
        WHERE vehicle_id = '${widget.vehicleId}' AND signal_name = 'soc' 
        ORDER BY timestamp ASC;
      ''');

      final spots = <FlSpot>[];
      for (int i = 0; i < rows.length; i++) {
        final val = (rows[i][1] as num).toDouble();
        spots.add(FlSpot(i.toDouble(), val));
      }

      if (mounted) {
        setState(() {
          _socHistorySpots = spots;
          _isLoadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  void _showDismissReasonSheet(Alert alert) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReasonSheetModal(
        onDismiss: (reason) async {
          final repo = ref.read(fleetRepositoryProvider);
          await repo.alertEngine.dismissAlert(alert.id, reason);

          ref.invalidate(activeAlertsProvider(widget.vehicleId));
          ref.invalidate(vehicleListProvider);

          if (!mounted) return;

          // Display 5-second UNDO snackbar (Section 3.C)
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF10B981)),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      'Alert dismissed (${alert.alertType.label})',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'UNDO',
                textColor: const Color(0xFF38BDF8),
                onPressed: () async {
                  await repo.alertEngine.undoDismissal(alert.id);
                  ref.invalidate(activeAlertsProvider(widget.vehicleId));
                  ref.invalidate(vehicleListProvider);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicleAsync = ref.watch(vehicleDetailProvider(widget.vehicleId));
    final alertsAsync = ref.watch(activeAlertsProvider(widget.vehicleId));
    final tripsAsync = ref.watch(vehicleTripsProvider(widget.vehicleId));

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text('Vehicle Readings Register'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(vehicleDetailProvider(widget.vehicleId));
              ref.invalidate(activeAlertsProvider(widget.vehicleId));
              ref.invalidate(vehicleTripsProvider(widget.vehicleId));
              _loadSocHistory();
            },
          ),
        ],
      ),
      body: vehicleAsync.when(
        data: (Vehicle? vehicle) {
          if (vehicle == null) {
            return const Center(child: Text('Vehicle not found', style: TextStyle(color: Colors.white)));
          }

          final status = vehicle.calculateStatus();
          final readings = VerdictEngine.evaluateVehicleSignals(
            soc: vehicle.soc,
            rangeKm: vehicle.rangeKm,
            speed: vehicle.speed,
            batteryTemp: vehicle.batteryTemp,
            odometer: vehicle.odometer,
            ignition: vehicle.ignition,
            lastPing: vehicle.lastPing,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vehicle Header Card
                Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.regNumber,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4.0),
                          Text(
                            vehicle.model,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14.0,
                            ),
                          ),
                          const SizedBox(height: 6.0),
                          Row(
                            children: [
                              Icon(
                                vehicle.currentGeofenceName != null ? Icons.fmd_good : Icons.navigation_outlined,
                                size: 14.0,
                                color: vehicle.currentGeofenceName != null ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6.0),
                              Text(
                                'Geofence: ${vehicle.currentGeofenceName ?? 'In Transit'}',
                                style: TextStyle(
                                  color: vehicle.currentGeofenceName != null ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      StatusChip(status: status),
                    ],
                  ),
                ),
                const SizedBox(height: 16.0),

                // Active Alerts Banner Section
                alertsAsync.when(
                  data: (alerts) {
                    if (alerts.isEmpty) return const SizedBox();
                    return Column(
                      children: alerts.map((alert) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          padding: const EdgeInsets.all(14.0),
                          decoration: BoxDecoration(
                            color: alert.severity == AlertSeverity.critical
                                ? const Color(0xFF7F1D1D).withOpacity(0.3)
                                : const Color(0xFF78350F).withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: alert.severity == AlertSeverity.critical ? Colors.redAccent : Colors.amber,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: alert.severity == AlertSeverity.critical ? Colors.redAccent : Colors.amber,
                                size: 24.0,
                              ),
                              const SizedBox(width: 12.0),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      alert.alertType.label,
                                      style: TextStyle(
                                        color: alert.severity == AlertSeverity.critical ? Colors.redAccent : Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15.0,
                                      ),
                                    ),
                                    const SizedBox(height: 2.0),
                                    Text(
                                      'Triggered: ${DateFormat('HH:mm:ss').format(alert.triggeredAt)} (${alert.severity.label})',
                                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.0),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                ),
                                onPressed: () => _showDismissReasonSheet(alert),
                                child: const Text('Dismiss'),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                ),

                // Signal Readings Register Table (Section 3.B)
                const Text(
                  'Signal Readings Register',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12.0),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: readings.length,
                    separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1.0),
                    itemBuilder: (context, index) {
                      final item = readings[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.0,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2.0),
                                  Text(
                                    'Age: ${item.ageFormatted}',
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                item.displayValue,
                                style: TextStyle(
                                  color: item.hasNeverReported ? const Color(0xFF64748B) : const Color(0xFF38BDF8),
                                  fontSize: 15.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            VerdictPill(verdict: item.verdict),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24.0),

                // SOC History Sparkline (Section 3.B)
                const Text(
                  'SOC Event Log History (Retained Window)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12.0),
                Container(
                  height: 200.0,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: _isLoadingHistory
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                      : _socHistorySpots.isEmpty
                          ? const Center(child: Text('No SOC history records in DuckDB', style: TextStyle(color: Color(0xFF94A3B8))))
                          : LineChart(
                              LineChartData(
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFF334155), strokeWidth: 1),
                                ),
                                titlesData: const FlTitlesData(
                                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: false),
                                minY: 0,
                                maxY: 100,
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _socHistorySpots,
                                    isCurved: true,
                                    color: const Color(0xFF38BDF8),
                                    barWidth: 3,
                                    dotData: const FlDotData(show: true),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                ),
                const SizedBox(height: 24.0),

                // Vehicle Trip History (Section 3.E)
                const Text(
                  'Automatic Trips (Geofence Engine)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12.0),
                tripsAsync.when(
                  data: (trips) {
                    if (trips.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16.0),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Text('No trips recorded yet for this vehicle.', style: TextStyle(color: Color(0xFF94A3B8))),
                      );
                    }
                    return Column(
                      children: trips.map((t) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          padding: const EdgeInsets.all(14.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    t.status == TripStatus.completed ? Icons.check_circle : Icons.directions_run,
                                    color: t.status == TripStatus.completed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                  ),
                                  const SizedBox(width: 12.0),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${t.originGeofenceName} ➔ ${t.destinationGeofenceName}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2.0),
                                      Text(
                                        'Started: ${DateFormat('MMM dd, HH:mm').format(t.startTime)}',
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.0),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                t.status.label,
                                style: TextStyle(
                                  color: t.status == TripStatus.completed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.0,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const CircularProgressIndicator(color: Color(0xFF38BDF8)),
                  error: (_, __) => const SizedBox(),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
        error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent))),
      ),
    );
  }
}
