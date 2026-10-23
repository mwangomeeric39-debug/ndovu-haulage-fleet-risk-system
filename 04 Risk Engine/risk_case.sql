CREATE TABLE IF NOT EXISTS fleet_catalog.risk.risk_case (
    alert_key STRING,
    risk_type STRING,
    vehicle_id STRING,
    status STRING,
    owner STRING,
    action_taken STRING,
    outcome STRING,
    cleared_for_dispatch BOOLEAN,
    opened_ts TIMESTAMP,
    closed_ts TIMESTAMP);