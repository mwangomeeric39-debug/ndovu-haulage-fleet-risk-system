CREATE OR REPLACE TABLE fleet_catalog.silver.stg_dispatch AS

SELECT
    dispatch_id,
    trip_id,
    vehicle_id,
    TRY_CAST(dispatched_ts AS TIMESTAMP) AS dispatched_ts,
    dispatcher,
    dispatch_channel
FROM fleet_catalog.bronze.dispatch_log
WHERE dispatch_id IS NOT NULL;