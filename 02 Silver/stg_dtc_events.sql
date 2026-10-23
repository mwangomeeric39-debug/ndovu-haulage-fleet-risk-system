CREATE OR REPLACE TABLE fleet_catalog.silver.stg_dtc_events AS

SELECT
    event_id,
    vehicle_id,
    dtc_code,
    description,
    severity,
    TRY_CAST(raised_ts AS TIMESTAMP) AS raised_ts,
    TRY_CAST(cleared_ts AS TIMESTAMP) AS cleared_ts,
    TRY_CAST(cleared_ts AS TIMESTAMP) IS NULL AS is_active,
    TRY_CAST(lat AS DOUBLE) AS lat,
    TRY_CAST(lon AS DOUBLE) AS lon
FROM fleet_catalog.bronze.dtc_events
WHERE event_id IS NOT NULL
AND vehicle_id IS NOT NULL;