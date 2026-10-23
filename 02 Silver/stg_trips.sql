CREATE OR REPLACE TABLE fleet_catalog.silver.stg_trips AS

SELECT
    trip_id,
    vehicle_id,
    driver_id,
    route_id,
    TRY_CAST(planned_start_ts AS TIMESTAMP) AS planned_start_ts,
    TRY_CAST(planned_end_ts AS TIMESTAMP) AS planned_end_ts,
    TRY_CAST(actual_start_ts AS TIMESTAMP) AS actual_start_ts,
    TRY_CAST(actual_end_ts AS TIMESTAMP) AS actual_end_ts,
    cargo_type,
    TRY_CAST(cargo_value_usd AS DOUBLE) AS cargo_value_usd,
    TRY_CAST(load_pct AS INT) AS load_pct,
    TRY_CAST(sla_hours AS DOUBLE) AS sla_hours,
    TRY_CAST(sla_penalty_per_hour_usd AS DOUBLE) AS sla_penalty_per_hour_usd,
    TRY_CAST(odometer_start_km AS DOUBLE) AS odometer_start_km,
    TRY_CAST(odometer_end_km AS DOUBLE) AS odometer_end_km,
    TRY_CAST(odometer_end_km AS DOUBLE)
        - TRY_CAST(odometer_start_km AS DOUBLE) AS distance_km,
    trip_status

FROM fleet_catalog.bronze.trips

WHERE trip_id IS NOT NULL
  AND vehicle_id IS NOT NULL;