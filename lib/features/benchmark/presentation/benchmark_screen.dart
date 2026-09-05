import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/fleet_providers.dart';
import '../data/scale_generator.dart';

class BenchmarkScreen extends ConsumerStatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  ConsumerState<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends ConsumerState<BenchmarkScreen> {
  String? _errorMessage;

  Future<void> _runBenchmark() async {
    final isRunning = ref.read(isBenchmarkRunningProvider);
    if (isRunning) return;

    ref.read(isBenchmarkRunningProvider.notifier).state = true;
    ref.read(benchmarkProgressProvider.notifier).state = 0.0;
    ref.read(benchmarkStatusProvider.notifier).state = 'Starting scale generator...';
    ref.read(benchmarkReportProvider.notifier).state = null;
    setState(() {
      _errorMessage = null;
    });

    try {
      final dbService = ref.read(duckDBServiceProvider);
      final generator = ScaleGenerator(dbService);

      final report = await generator.runScaleBackfillAndBenchmark(
        onProgress: (p, msg) {
          ref.read(benchmarkProgressProvider.notifier).state = p;
          ref.read(benchmarkStatusProvider.notifier).state = msg;
        },
      );

      ref.invalidate(vehicleListProvider);
      ref.invalidate(fleetStatusCountsProvider);

      ref.read(benchmarkReportProvider.notifier).state = report;
      ref.read(benchmarkStatusProvider.notifier).state = 'Scale benchmark completed successfully!';
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
      ref.read(benchmarkStatusProvider.notifier).state = 'Benchmark error encountered.';
    } finally {
      ref.read(isBenchmarkRunningProvider.notifier).state = false;
    }
  }

  Future<void> _runLogCompaction() async {
    final dbService = ref.read(duckDBServiceProvider);
    final generator = ScaleGenerator(dbService);

    final pruned = await generator.runLogCompaction(retentionDays: 7);
    ref.invalidate(vehicleListProvider);
    ref.invalidate(fleetStatusCountsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Log compaction completed. Pruned $pruned raw signal rows older than 7 days.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = ref.watch(isBenchmarkRunningProvider);
    final progress = ref.watch(benchmarkProgressProvider);
    final statusMessage = ref.watch(benchmarkStatusProvider);
    final report = ref.watch(benchmarkReportProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text('Scale Benchmark & Log Retention'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exercise Description Card
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed, color: Color(0xFFF59E0B)),
                      SizedBox(width: 8.0),
                      Text(
                        'Scale Exercise (Section 4)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.0),
                  Text(
                    'Generates 500 electric vehicles and 2,000,000+ signal telemetry rows in DuckDB. Measures cold start time, warm p50/p95 SQL query latency, and memory footprint at rest.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.0, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20.0),

            // Progress & Trigger Button
            SizedBox(
              width: double.infinity,
              height: 50.0,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning ? const Color(0xFF334155) : const Color(0xFFF59E0B),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                ),
                onPressed: isRunning ? null : _runBenchmark,
                icon: const Icon(Icons.rocket_launch, fontWeight: FontWeight.bold),
                label: Text(
                  isRunning ? 'Backfilling 2M Telemetry Rows...' : 'Run 2 Million Telemetry Benchmark',
                  style: const TextStyle(fontSize: 15.0, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12.0),

            if (isRunning) ...[
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: const Color(0xFF1E293B),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                minHeight: 8.0,
              ),
              const SizedBox(height: 8.0),
            ],
            Text(
              statusMessage,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.0),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12.0),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12.0),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24.0),

            // Benchmark Report Card
            if (report != null) ...[
              const Text(
                'Benchmark Metrics Report',
                style: TextStyle(color: Colors.white, fontSize: 18.0, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12.0),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Column(
                  children: [
                    _buildMetricRow('Vehicles Backfilled', '${report.vehicleCount}'),
                    const Divider(color: Color(0xFF334155)),
                    _buildMetricRow('Total Signal Rows', report.totalSignalRows.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')),
                    const Divider(color: Color(0xFF334155)),
                    _buildMetricRow('Backfill Execution Time', '${report.backfillDurationSeconds.toStringAsFixed(2)} seconds'),
                    const Divider(color: Color(0xFF334155)),
                    _buildMetricRow('Fleet List Query p50 Latency', '${report.p50QueryLatencyMs.toStringAsFixed(2)} ms'),
                    const Divider(color: Color(0xFF334155)),
                    _buildMetricRow('Fleet List Query p95 Latency', '${report.p95QueryLatencyMs.toStringAsFixed(2)} ms'),
                    const Divider(color: Color(0xFF334155)),
                    _buildMetricRow('Memory Footprint at Rest (RSS)', '${report.memoryUsageMb.toStringAsFixed(1)} MB'),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),
            ],

            // Retention Policy & Log Compaction Section
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(color: const Color(0xFF38BDF8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cleaning_services, color: Color(0xFF38BDF8)),
                      SizedBox(width: 8.0),
                      Text(
                        'Log Compaction & Retention Policy',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  const Text(
                    'Append-only telemetry logs grow continuously. Our policy prunes raw high-frequency signal rows older than 7 days while preserving geofence events, trip boundaries, and alert histories intact.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.0, height: 1.4),
                  ),
                  const SizedBox(height: 14.0),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8)),
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                      ),
                      onPressed: isRunning ? null : _runLogCompaction,
                      icon: const Icon(Icons.auto_delete_outlined),
                      label: const Text('Execute Log Compaction (Keep 7-Day Log)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14.0)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 15.0, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
