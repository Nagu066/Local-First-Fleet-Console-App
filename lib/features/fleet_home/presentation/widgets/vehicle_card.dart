import 'package:flutter/material.dart';
import '../../../../core/models/vehicle.dart';
import 'status_chip.dart';

class VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final VoidCallback onTap;

  const VehicleCard({
    super.key,
    required this.vehicle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = vehicle.calculateStatus();
    final soc = vehicle.soc ?? 0.0;

    Color socColor;
    if (soc < 10.0) {
      socColor = Colors.redAccent;
    } else if (soc < 20.0) {
      socColor = Colors.orangeAccent;
    } else {
      socColor = const Color(0xFF10B981);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      elevation: 2.0,
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(
          color: vehicle.hasActiveAlert
              ? Colors.redAccent.withOpacity(0.6)
              : const Color(0xFF334155),
          width: vehicle.hasActiveAlert ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        child: const Icon(
                          Icons.local_shipping,
                          color: Color(0xFF38BDF8),
                          size: 22.0,
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.regNumber,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            vehicle.model,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (vehicle.hasActiveAlert)
                        Container(
                          margin: const EdgeInsets.only(right: 8.0),
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(color: Colors.redAccent, width: 1.0),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 14.0, color: Colors.redAccent),
                              SizedBox(width: 4.0),
                              Text(
                                'ALERT',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      StatusChip(status: status, isCompact: true),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Battery (SOC)',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12.0,
                              ),
                            ),
                            Text(
                              vehicle.soc != null ? '${soc.toStringAsFixed(0)}%' : '—',
                              style: TextStyle(
                                color: socColor,
                                fontSize: 13.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6.0),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4.0),
                          child: LinearProgressIndicator(
                            value: vehicle.soc != null ? (soc / 100.0).clamp(0.0, 1.0) : 0.0,
                            backgroundColor: const Color(0xFF0F172A),
                            valueColor: AlwaysStoppedAnimation<Color>(socColor),
                            minHeight: 6.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24.0),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Est. Range',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12.0,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        vehicle.rangeKm != null ? '${vehicle.rangeKm!.toStringAsFixed(1)} km' : '—',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
