%sql
CREATE OR REPLACE TABLE fleet_catalog.silver.stg_maintenance_orders AS

SELECT
    wo_id,
    vehicle_id,
    wo_type,
    TRY_CAST(opened_ts AS TIMESTAMP) AS opened_ts,
    TRY_CAST(closed_ts AS TIMESTAMP) AS closed_ts,

    (UNIX_TIMESTAMP(TRY_CAST(closed_ts AS TIMESTAMP))
        - UNIX_TIMESTAMP(TRY_CAST(opened_ts AS TIMESTAMP))) / 3600.0 AS downtime_hours,
    workshop,
    root_cause,
    parts_used,
    TRY_CAST(parts_cost_usd AS DOUBLE) AS parts_cost_usd,
    TRY_CAST(labour_cost_usd AS DOUBLE) AS labour_cost_usd,
    TRY_CAST(recovery_cost_usd AS DOUBLE) AS recovery_cost_usd,

    TRY_CAST(parts_cost_usd AS DOUBLE)
        + TRY_CAST(labour_cost_usd AS DOUBLE)
        + TRY_CAST(recovery_cost_usd AS DOUBLE) AS total_cost_usd
FROM fleet_catalog.bronze.maintenance_orders
WHERE wo_id IS NOT NULL
AND vehicle_id IS NOT NULL;