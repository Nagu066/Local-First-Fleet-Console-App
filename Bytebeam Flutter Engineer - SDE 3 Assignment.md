## Flutter Take-Home — Fleet Console (Local-First)

Role: Flutter Engineer (SDE-3), Bytebeam Expected effort: 14–16 hours across a week. We do not time you. A smaller scope done well beats everything done thinly — if you cut, say what you cut and why. Tools: Use AI assistants freely. We build with them daily. Two conditions follow: you share your conversation logs, and you defend every decisions in a live session. Code you cannot explain counts against you more than code you did not write.

The difficulty is not volume of features — it is that the data model has genuinely ambiguous cases, and we want to see how you resolve them.

## 1. Context

A fleet operator with 500 electric trucks needs one screen answering: where are my vehicles, are they okay, what needs attention now.

Vehicles emit telemetry — small sensor packets over a flaky mobile link. Packets arrive late, out of order, duplicated, or not at all. Vehicles park in basements for hours and then dump a backlog.

Glossary. SOC — battery state of charge, %. Range — estimated km remaining. Odometer — lifetime km. Ignition — vehicle switched on. Signal — one named telemetry parameter (soc, speed, battery_temp, …). Packet — one timestamped emission from one vehicle, carrying a subset of signals. Stale — last report too old to trust.

## 2. Architecture requirement — local-first over DuckDB

The app is local-first. Telemetry is written to an embedded DuckDB database on device (dart_duckdb, currently ^1.2.0 — ships its own binaries, works on Android). The UI reads from DuckDB. It does not read from an in-memory list that DuckDB happens to shadow. If you kill the app and relaunch it, everything the app knew must come back off disk.

## 3. Features

## A — Fleet home

List of all vehicles: reg number, model, SOC, range, alert badge, and a status chip (first match wins):

| Status | Rule |
| --- | --- |
| OFFLINE | vehicle-level last ping older than 10 min |
| MOVING | speed > 0 |
| IDLE | speed = 0 and ignition on |
| STOPPED | ignition off |

Filter chips (All / Moving / Idle / Stopped / Offline) with live counts, computed in SQL. Empty results get an empty state.


## B — Vehicle detail

A readings register: one row per signal (SOC, range, speed, battery temperature, odometer, last ping) with label, value, its own age, and a verdict pill — NORMAL (fresh, within threshold), ALERT (fresh, outside threshold), STALE (grey, too old to judge, no normal/alert claim). A signal that has never reported shows "—" with no pill.

Include a history sparkline or table for SOC over the retained window. You are storing an event log; show that you can query it.

## C — Alerts, dismissal, undo

Thresholds, on fresh readings only:

| Alert | Condition | Severity |
| --- | --- | --- |
| Low battery | SOC < 20% | Warning |
| Battery critically low | SOC < 10% | Critical |
| Battery overheating | battery temp > 45 °C | Critical |

The two SOC alerts are one escalating alert, not two. Dismissal opens a reason sheet — "I am on it", "Wrong alert", "Something else…", in that order — removes the alert and shows UNDO for 5 seconds. A condition that clears resolves its alert independently of dismissal.

## D — Geofences

Create, edit, and deactivate persisted circular geofences (name, centre, radius, active state), and show each vehicle’s current geofence plus live vehicle counts; seed at least three and retain deactivated geofences for trip history.

Determine entry and exit from event-time location history using a documented deterministic strategy for duplicates, late packets, GPS jitter, inaccurate readings, overlaps, missing intervals, and geofence edits.

## E — Automatic trips

Build trips automatically from confirmed geofence transitions:

| Transition | Result |
| --- | --- |
| Confirmed exit | Start a trip |
| Next confirmed entry | Complete the active trip |
| No confirmed entry | Keep it IN PROGRESS |

Returning to the origin geofence is valid, and a vehicle may have only one active trip. Processing must be idempotent and event-time aware: duplicate packets create nothing twice, while late packets may revise trip boundaries or destinations without producing duplicate trips.

## 4. Scale exercise

Ship a script or debug action that backfills 500 vehicles and at least 2 million signal rows. Then measure, on a real device or a named emulator:

- \- Cold start to first painted fleet list.


- \- The fleet-list query, p50 and p95, warm.

- \- Memory at rest with the list open.

Report the numbers, your method, and the device. If it is slow, say it is slow and say what you would do — a measured 900 ms with a diagnosis beats an unmeasured claim of 40 ms. Also state your retention policy: an append-only log grows forever, so what gets compacted or dropped, and what the app loses when it does.

## 5. Tests

You should provide a comprehensive test suite.

## 6. Deliverables

- 1. Private git repo, meaningful commit history, no single squashed commit. Commit messages in your own words.

- 2. README.md — run the app, run the tests, 30-second feature tour. APK optional.

- 3. AI conversation logs, uncurated. Dead ends and corrections are the interesting part.
