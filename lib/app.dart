import 'package:flutter/material.dart';
import 'features/fleet_home/presentation/fleet_home_screen.dart';

class FleetConsoleApp extends StatelessWidget {
  const FleetConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fleet Console',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const FleetHomeScreen(),
    );
  }
}
