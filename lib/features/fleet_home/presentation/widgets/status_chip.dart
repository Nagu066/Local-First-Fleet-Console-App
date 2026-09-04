import 'package:flutter/material.dart';
import '../../../../core/models/vehicle.dart';

class StatusChip extends StatelessWidget {
  final VehicleStatus status;
  final bool isCompact;

  const StatusChip({
    super.key,
    required this.status,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    IconData iconData;

    switch (status) {
      case VehicleStatus.moving:
        bgColor = const Color(0xFF064E3B);
        textColor = const Color(0xFF34D399);
        iconData = Icons.navigation;
        break;
      case VehicleStatus.idle:
        bgColor = const Color(0xFF78350F);
        textColor = const Color(0xFFFBBF24);
        iconData = Icons.pause_circle_filled;
        break;
      case VehicleStatus.stopped:
        bgColor = const Color(0xFF7F1D1D);
        textColor = const Color(0xFFFCA5A5);
        iconData = Icons.stop_circle;
        break;
      case VehicleStatus.offline:
        bgColor = const Color(0xFF1E293B);
        textColor = const Color(0xFF94A3B8);
        iconData = Icons.wifi_off;
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8.0 : 12.0,
        vertical: isCompact ? 4.0 : 6.0,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: textColor.withOpacity(0.3), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: isCompact ? 12.0 : 14.0, color: textColor),
          const SizedBox(width: 4.0),
          Text(
            status.label,
            style: TextStyle(
              color: textColor,
              fontSize: isCompact ? 11.0 : 12.0,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
