import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/providers/fleet_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create ProviderContainer to initialize DuckDB before running app
  final container = ProviderContainer();
  final dbService = container.read(duckDBServiceProvider);
  await dbService.init();

  final repo = container.read(fleetRepositoryProvider);
  await repo.seedInitialDataIfEmpty();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FleetConsoleApp(),
    ),
  );
}
