# Local-First Fleet Console App Implementation Plan

Building an enterprise-grade, local-first Flutter application for a fleet operator managing 500 electric trucks powered by embedded **DuckDB** (`dart_duckdb`), featuring real-time state calculation, alert handling, deterministic geofence entry/exit engine, automatic trip building, and a 2+ million telemetry record scale benchmark suite.

---

## User Review Required

> [!IMPORTANT]
> **Database Engine Choice**: We will use `dart_duckdb` (or high-performance DuckDB bindings) as mandated by section 2 of the assignment. All UI state, fleet summaries, signal registers, geofences, and trip histories will strictly be queried directly from DuckDB on disk.

> [!NOTE]
> **Scalability & Scale Exercise**: The scale benchmark script will be accessible directly in the app UI via a "Debug & Scale Benchmark" drawer/modal, allowing backfilling 500 vehicles and 2,000,000+ signal rows into DuckDB and recording cold start times, p50/p95 query latency, memory footprint, and demonstrating our log retention policy.

---

## Open Questions

None at present. Requirements in `Bytebeam Flutter Engineer - SDE 3 Assignment.md` are comprehensive and well-specified.

---

## Proposed Architecture & Component Design

```
lib/
├── core/
│   ├── database/
│   │   ├── duckdb_service.dart          # Local-first DuckDB connection, schemas, migrations & queries
│   │   └── schema.dart                  # DDL statements & SQL views
│   ├── engine/
│   │   ├── geofence_engine.dart         # Deterministic event-time geofence Entry/Exit detector
│   │   ├── trip_engine.dart             # Idempotent automatic trip builder from geofence transitions
│   │   └── alert_engine.dart            # Escalating alert evaluator & threshold manager
│   ├── models/
│   │   ├── vehicle.dart                 # Vehicle entity & calculated status
│   │   ├── telemetry_packet.dart        # Signal telemetry packet model
│   │   ├── geofence.dart                # Circular geofence definition
│   │   ├── trip.dart                    # Trip model (IN_PROGRESS / COMPLETED)
│   │   └── alert.dart                   # Alert model (Low battery, Critically low, Overheating)
│   └── utils/
│       ├── distance_calculator.dart     # Haversine distance & GPS jitter filter
│       └── formatting.dart              # UI text, date, & status pill helpers
├── features/
│   ├── fleet_home/
│   │   ├── data/fleet_repository.dart   # SQL queries for fleet list, filter counts, vehicle metrics
│   │   ├── presentation/
│   │   │   ├── fleet_home_screen.dart   # Search, Filter chips with live counts, vehicle list
│   │   │   └── widgets/                 # Vehicle card, status chip, alert badge
│   ├── vehicle_detail/
│   │   ├── presentation/
│   │   │   ├── vehicle_detail_screen.dart # Signal register view & SOC history sparkline
│   │   │   └── widgets/                 # Readings table, verdict pills, sparkline chart
│   ├── geofences/
│   │   ├── presentation/
│   │   │   ├── geofence_management_screen.dart # Create/edit/deactivate circular geofences
│   │   │   └── widgets/                 # Interactive/visual geofence list & vehicle counts
│   ├── alerts/
│   │   ├── presentation/
│   │   │   └── widgets/                 # Alert banner, Reason sheet modal ("I am on it", UNDO bar)
│   └── benchmark/
│       ├── data/scale_generator.dart    # High-throughput batch generator (500 vehicles, 2M+ telemetry rows)
│       └── presentation/
│           └── benchmark_screen.dart    # Benchmark runner UI & performance metrics report (cold start, p50/p95 latency, RAM)
├── app.dart
└── main.dart
```

---

## Detailed Step-by-Step Implementation Plan

### Step 1: Project Initialization & Dependency Setup
- Initialize clean Flutter application.
- Add required dependencies in `pubspec.yaml`:
  - `dart_duckdb` / `duckdb`: Embedded DuckDB database engine.
  - `flutter_riverpod` or `provider` / `bloc`: Clean state management layer.
  - `fl_chart`: For SOC signal history sparkline & performance benchmark charts.
  - `latlong2`: For GPS coordinate distance calculations.
  - `flutter_test`: Unit & integration testing.

### Step 2: Local-First DuckDB Architecture & Data Layer
- **Database Schema**:
  - `vehicles`: `id`, `reg_number`, `model`, `created_at`
  - `telemetry_signals`: `id`, `vehicle_id`, `signal_name`, `value`, `unit`, `timestamp`, `ingested_at` (Indexed on `vehicle_id`, `timestamp`, `signal_name`)
  - `geofences`: `id`, `name`, `center_lat`, `center_lng`, `radius_meters`, `is_active`, `created_at`
  - `geofence_events`: `id`, `vehicle_id`, `geofence_id`, `event_type` (`ENTRY`/`EXIT`), `timestamp`
  - `trips`: `id`, `vehicle_id`, `origin_geofence_id`, `destination_geofence_id`, `start_time`, `end_time`, `status` (`IN_PROGRESS`/`COMPLETED`), `distance_km`
  - `alerts`: `id`, `vehicle_id`, `alert_type`, `severity`, `status` (`ACTIVE`/`DISMISSED`/`RESOLVED`), `dismissal_reason`, `triggered_at`, `resolved_at`
- **SQL Analytics Views**:
  - `v_latest_vehicle_status`: High performance SQL aggregation joining latest `soc`, `range`, `speed`, `battery_temp`, `odometer`, `ignition`, `lat`, `lng`, and last ping timestamp per vehicle.

### Step 3: Core Domain Engines

#### A. Status Engine (First Match Wins)
1. `OFFLINE`: Vehicle-level last ping > 10 mins ago (`now - last_ping > 600s`)
2. `MOVING`: `speed > 0`
3. `IDLE`: `speed == 0` AND `ignition == true`
4. `STOPPED`: `ignition == false`

#### B. Verdict Pill & Signal Freshness Engine
- Compare signal timestamp to current time.
- If age > threshold (e.g. > 15 mins), verdict = `STALE` (grey pill).
- If fresh:
  - Check thresholds:
    - SOC: `< 20%` (Warning), `< 10%` (Critical) -> `ALERT` pill if triggered, else `NORMAL`.
    - Battery temp: `> 45 °C` (Critical) -> `ALERT` pill, else `NORMAL`.
- Unreported signals display `—` with no pill.

#### C. Alert & Escalation Engine with Dismissal & Undo
- Single escalating SOC alert rule (`Low battery` < 20%, `Battery critically low` < 10%).
- Condition clearing: Telemetry value returning to normal automatically resolves active alert independently of user dismissal.
- Dismissal flow: Triggers Reason Sheet ("I am on it", "Wrong alert", "Something else…"), updates DuckDB status to `DISMISSED`, displays 5-second `UNDO` snackbar.

#### D. Deterministic Geofence Entry/Exit Engine
- Event-time processing pipeline handling duplicate packets, out-of-order late arrivals, GPS jitter (hysteresis radius window & speed filter), overlaps (closest geofence center), and geofence edits.
- Persist `geofence_events` (`ENTRY` / `EXIT`) idempotently using unique constraint `(vehicle_id, geofence_id, event_type, timestamp)`.

#### E. Automatic Trip Building Engine
- Event-driven state machine listening to confirmed geofence transitions:
  - `Confirmed exit`: Create new trip record with status `IN_PROGRESS` and `origin_geofence_id`.
  - `Next confirmed entry`: Update active trip to `COMPLETED`, set `destination_geofence_id`, `end_time`, `distance_km`.
  - `No confirmed entry`: Maintain `IN_PROGRESS` status.
  - Round trips allowed (origin == destination). Enforce single active trip invariant per vehicle.

### Step 4: UI Development (Rich Premium Design)

#### A. Fleet Home Screen
- Search bar for registration number / model.
- Dynamic Filter Chips (`All`, `Moving`, `Idle`, `Stopped`, `Offline`) with live SQL counts.
- Vehicle list cards displaying reg number, model, current SOC, range, alert badge (with severity tint), and vehicle status chip.
- Empty state visual component for no matching filter/search.

#### B. Vehicle Detail Screen
- Header banner showing vehicle identity & current status.
- **Readings Register**: List/Table of signals (`SOC`, `Range`, `Speed`, `Battery Temp`, `Odometer`, `Last Ping`), showing label, value, signal age, and Verdict Pill (`NORMAL`, `ALERT`, `STALE`).
- **SOC History Sparkline/Chart**: Rendered directly from DuckDB event log query over retained window.
- Active Alerts section with Dismiss button.

#### C. Geofences Management Screen
- Seed 3 default circular geofences ("Depot Alpha", "Charging Hub East", "Logistics Terminal").
- Interface to create, edit center/radius, and soft-delete/deactivate geofences.
- Vehicle presence counters for each active geofence.

#### D. Trip History Screen
- Displays completed and in-progress trips built automatically from geofence transitions.

### Step 5: Scale Benchmark & Retention Policy Suite (Section 4)
- **Data Generator**: Script/Action populating DuckDB with **500 vehicles** and **2,000,000+ telemetry rows**.
- **Benchmark Metrics Runner**:
  - Cold start time measurement (app launch to first painted list).
  - SQL query execution latency (p50 and p95 benchmarks across 100 iterations).
  - Rest memory footprint tracking.
- **Retention Policy Implementation**:
  - Event log compaction: Pruning raw high-frequency telemetry older than N days while aggregating hourly/daily SOC stats and keeping geofence events + trip logs intact.

### Step 6: Comprehensive Automated Tests (Section 5)
- **Unit Tests**:
  - DuckDB queries, schema migrations, views.
  - Telemetry parser & signal freshness verdict rules.
  - Alert escalation, dismissal, condition self-clearing, and undo.
  - Geofence entry/exit algorithm with out-of-order & duplicate packets.
  - Automatic trip generator logic.
- **Widget & Integration Tests**:
  - Vehicle card rendering & filter chip switching.
  - Reason sheet modal & 5-second undo timer test.

### Step 7: Documentation & Deliverables
- `README.md` containing run instructions, testing commands, scale benchmark guide, retention policy details, and feature tour.

---

## Verification Plan

### Automated Verification
```bash
# Run unit & integration tests
flutter test

# Run static analysis
flutter analyze
```

### Manual & Benchmark Verification
1. **Local-First Check**: Terminate app, restart app, verify all vehicles, geofences, alerts, and trip histories reload cleanly from DuckDB.
2. **Scale Exercise**: Trigger "Run 2 Million Telemetry Benchmark" in benchmark UI, observe batch insert performance, view p50/p95 latency report and memory metrics.
3. **Alert Dismissal & Undo**: Trigger low battery alert, dismiss with reason "I am on it", observe 5-second UNDO snackbar, tap UNDO and verify alert restores to ACTIVE.
4. **Geofence & Automatic Trips**: Simulate a sequence of lat/lng telemetry points exiting "Depot Alpha" and entering "Charging Hub East", verify automatic creation and completion of Trip.
