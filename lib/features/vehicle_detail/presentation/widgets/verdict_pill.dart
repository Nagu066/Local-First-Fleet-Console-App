import 'package:flutter/material.dart';
import '../../../../core/engine/verdict_engine.dart';

class VerdictPill extends StatelessWidget {
  final SignalVerdict? verdict;

  const VerdictPill({super.key, this.verdict});

  @override
  Widget build(BuildContext context) {
    if (verdict == null) return const SizedBox();

    Color bgColor;
    Color textColor;

    switch (verdict!) {
      case SignalVerdict.normal:
        bgColor = const Color(0xFF064E3B);
        textColor = const Color(0xFF34D399);
        break;
      case SignalVerdict.alert:
        bgColor = const Color(0xFF7F1D1D);
        textColor = const Color(0xFFFCA5A5);
        break;
      case SignalVerdict.stale:
        bgColor = const Color(0xFF1E293B);
        textColor = const Color(0xFF94A3B8);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: textColor.withOpacity(0.4), width: 1.0),
      ),
      child: Text(
        verdict!.label,
        style: TextStyle(
          color: textColor,
          fontSize: 11.0,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
