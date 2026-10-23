CREATE OR REPLACE TABLE fleet_catalog.silver.stg_fuel_events AS

SELECT
    reading_id AS event_id,
    vehicle_id,
    trip_id,
    reading_ts AS event_ts,
    lat,
    lon,
    ignition_on,
    fuel_delta_l,
    gap_min,
    CASE
        WHEN fuel_delta_l <= -20
        AND gap_min <= 90
        AND COALESCE(speed_kph, 0) < 5
        AND COALESCE(prev_speed_kph, 0) < 5
        THEN 'SIPHON_SUSPECT'

        WHEN fuel_delta_l >= 25
        THEN 'REFUEL'
    END AS event_type
FROM fleet_catalog.silver.stg_telemetry
WHERE fuel_delta_l <= -20
OR fuel_delta_l >= 25;