/// Database Schema DDL and Queries for Local-First DuckDB Fleet Console

class DatabaseSchema {
  static const String createVehiclesTable = '''
    CREATE TABLE IF NOT EXISTS vehicles (
      id VARCHAR PRIMARY KEY,
      reg_number VARCHAR NOT NULL UNIQUE,
      model VARCHAR NOT NULL,
      created_at TIMESTAMP NOT NULL
    );
  ''';

  static const String createTelemetrySignalsTable = '''
    CREATE TABLE IF NOT EXISTS telemetry_signals (
      id VARCHAR PRIMARY KEY,
      vehicle_id VARCHAR NOT NULL,
      signal_name VARCHAR NOT NULL,
      value DOUBLE NOT NULL,
      unit VARCHAR,
      timestamp TIMESTAMP NOT NULL,
      ingested_at TIMESTAMP NOT NULL
    );
  ''';

  static const String createTelemetryIndexes = '''
    CREATE INDEX IF NOT EXISTS idx_telemetry_v_sig_ts ON telemetry_signals (vehicle_id, signal_name, timestamp);
    CREATE INDEX IF NOT EXISTS idx_telemetry_v_ts ON telemetry_signals (vehicle_id, timestamp);
  ''';

  static const String createGeofencesTable = '''
    CREATE TABLE IF NOT EXISTS geofences (
      id VARCHAR PRIMARY KEY,
      name VARCHAR NOT NULL,
      center_lat DOUBLE NOT NULL,
      center_lng DOUBLE NOT NULL,
      radius_meters DOUBLE NOT NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMP NOT NULL,
      updated_at TIMESTAMP NOT NULL
    );
  ''';

  static const String createGeofenceEventsTable = '''
    CREATE TABLE IF NOT EXISTS geofence_events (
      id VARCHAR PRIMARY KEY,
      vehicle_id VARCHAR NOT NULL,
      geofence_id VARCHAR NOT NULL,
      event_type VARCHAR NOT NULL, -- 'ENTRY' or 'EXIT'
      timestamp TIMESTAMP NOT NULL,
      packet_timestamp TIMESTAMP NOT NULL
    );
  ''';

  static const String createGeofenceEventsIndex = '''
    CREATE INDEX IF NOT EXISTS idx_geofence_events_v_ts ON geofence_events (vehicle_id, timestamp);
  ''';

  static const String createTripsTable = '''
    CREATE TABLE IF NOT EXISTS trips (
      id VARCHAR PRIMARY KEY,
      vehicle_id VARCHAR NOT NULL,
      origin_geofence_id VARCHAR NOT NULL,
      destination_geofence_id VARCHAR,
      start_time TIMESTAMP NOT NULL,
      end_time TIMESTAMP,
      status VARCHAR NOT NULL, -- 'IN_PROGRESS' or 'COMPLETED'
      start_lat DOUBLE,
      start_lng DOUBLE,
      end_lat DOUBLE,
      end_lng DOUBLE,
      distance_km DOUBLE DEFAULT 0.0
    );
  ''';

  static const String createTripsIndex = '''
    CREATE INDEX IF NOT EXISTS idx_trips_v_status ON trips (vehicle_id, status);
  ''';

  static const String createAlertsTable = '''
    CREATE TABLE IF NOT EXISTS alerts (
      id VARCHAR PRIMARY KEY,
      vehicle_id VARCHAR NOT NULL,
      alert_type VARCHAR NOT NULL, -- 'LOW_BATTERY', 'CRITICAL_BATTERY', 'BATTERY_OVERHEATING'
      severity VARCHAR NOT NULL, -- 'WARNING', 'CRITICAL'
      status VARCHAR NOT NULL, -- 'ACTIVE', 'DISMISSED', 'RESOLVED'
      dismissal_reason VARCHAR,
      triggered_at TIMESTAMP NOT NULL,
      updated_at TIMESTAMP NOT NULL,
      dismissed_at TIMESTAMP,
      resolved_at TIMESTAMP
    );
  ''';

  static const String createAlertsIndex = '''
    CREATE INDEX IF NOT EXISTS idx_alerts_v_status ON alerts (vehicle_id, status);
  ''';

  /// View to extract the latest telemetry readings per vehicle
  static const String createLatestVehicleStatusView = '''
    CREATE OR REPLACE VIEW v_latest_vehicle_status AS
    WITH max_pings AS (
      SELECT 
        vehicle_id,
        MAX(timestamp) AS last_ping
      FROM telemetry_signals
      GROUP BY vehicle_id
    ),
    latest_signals AS (
      SELECT 
        ts.vehicle_id,
        ts.signal_name,
        ts.value,
        ts.timestamp,
        ROW_NUMBER() OVER (PARTITION BY ts.vehicle_id, ts.signal_name ORDER BY ts.timestamp DESC) as rn
      FROM telemetry_signals ts
    )
    SELECT 
      v.id as vehicle_id,
      v.reg_number,
      v.model,
      mp.last_ping,
      soc.value as soc,
      range.value as range_km,
      speed.value as speed,
      temp.value as battery_temp,
      odo.value as odometer,
      ign.value as ignition,
      lat.value as latitude,
      lng.value as longitude
    FROM vehicles v
    LEFT JOIN max_pings mp ON v.id = mp.vehicle_id
    LEFT JOIN latest_signals soc ON v.id = soc.vehicle_id AND soc.signal_name = 'soc' AND soc.rn = 1
    LEFT JOIN latest_signals range ON v.id = range.vehicle_id AND range.signal_name = 'range' AND range.rn = 1
    LEFT JOIN latest_signals speed ON v.id = speed.vehicle_id AND speed.signal_name = 'speed' AND speed.rn = 1
    LEFT JOIN latest_signals temp ON v.id = temp.vehicle_id AND temp.signal_name = 'battery_temp' AND temp.rn = 1
    LEFT JOIN latest_signals odo ON v.id = odo.vehicle_id AND odo.signal_name = 'odometer' AND odo.rn = 1
    LEFT JOIN latest_signals ign ON v.id = ign.vehicle_id AND ign.signal_name = 'ignition' AND ign.rn = 1
    LEFT JOIN latest_signals lat ON v.id = lat.vehicle_id AND lat.signal_name = 'latitude' AND lat.rn = 1
    LEFT JOIN latest_signals lng ON v.id = lng.vehicle_id AND lng.signal_name = 'longitude' AND lng.rn = 1;
  ''';
}
