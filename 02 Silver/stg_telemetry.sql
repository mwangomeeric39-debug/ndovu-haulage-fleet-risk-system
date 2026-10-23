CREATE OR REPLACE TABLE fleet_catalog.silver.stg_telemetry AS

WITH typed AS (
    SELECT
        reading_id,
        vehicle_id,
        NULLIF(trip_id, '') AS trip_id,
        TRY_CAST(reading_ts AS TIMESTAMP) AS reading_ts,
        TRY_CAST(lat AS DOUBLE) AS lat,
        TRY_CAST(lon AS DOUBLE) AS lon,
        TRY_CAST(speed_kph AS DOUBLE) AS speed_kph,
        TRY_CAST(engine_rpm AS DOUBLE) AS engine_rpm,
        TRY_CAST(engine_load_pct AS DOUBLE) AS engine_load_pct,
        TRY_CAST(coolant_temp_c AS DOUBLE) AS coolant_temp_c,
        TRY_CAST(oil_pressure_kpa AS DOUBLE) AS oil_pressure_kpa,
        TRY_CAST(transmission_temp_c AS DOUBLE) AS transmission_temp_c,
        TRY_CAST(battery_v AS DOUBLE) AS battery_v,
        TRY_CAST(fuel_level_pct AS DOUBLE) AS fuel_level_pct,
        TRY_CAST(ignition_on AS INT) AS ignition_on,
        TRY_CAST(odometer_km AS DOUBLE) AS odometer_km,
        TRY_CAST(brake_pad_wear_pct AS DOUBLE) AS brake_pad_wear_pct

    FROM fleet_catalog.bronze.telemetry

    WHERE vehicle_id IS NOT NULL
      AND TRY_CAST(reading_ts AS TIMESTAMP) IS NOT NULL
),

cleaned AS (
    SELECT
        reading_id,
        vehicle_id,
        trip_id,
        reading_ts,

        IF(lat = 0 AND lon = 0, NULL, lat) AS lat,
        IF(lat = 0 AND lon = 0, NULL, lon) AS lon,
        IF(speed_kph BETWEEN 0 AND 140, speed_kph, NULL) AS speed_kph,
        IF(engine_rpm BETWEEN 0 AND 3500, engine_rpm, NULL) AS engine_rpm,
        IF(engine_load_pct BETWEEN 0 AND 100, engine_load_pct, NULL) AS engine_load_pct,
        IF(coolant_temp_c BETWEEN 0 AND 150, coolant_temp_c, NULL) AS coolant_temp_c,
        IF(oil_pressure_kpa BETWEEN 0 AND 800, oil_pressure_kpa, NULL) AS oil_pressure_kpa,
        IF(transmission_temp_c BETWEEN 0 AND 200, transmission_temp_c, NULL) AS transmission_temp_c,
        IF(battery_v BETWEEN 10 AND 32, battery_v, NULL) AS battery_v,
        IF(fuel_level_pct BETWEEN 0 AND 100, fuel_level_pct, NULL) AS fuel_level_pct,

        ignition_on,
        odometer_km,
        brake_pad_wear_pct,

        CASE
            WHEN (lat = 0 AND lon = 0)
              OR speed_kph IS NULL
              OR NOT (speed_kph BETWEEN 0 AND 140)
              OR coolant_temp_c IS NULL
              OR NOT (coolant_temp_c BETWEEN 0 AND 150)
              OR fuel_level_pct IS NULL
              OR NOT (fuel_level_pct BETWEEN 0 AND 100)
            THEN 1
            ELSE 0
        END AS dq_repaired

    FROM typed
),

filled AS (
    SELECT
        reading_id,
        vehicle_id,
        trip_id,
        reading_ts,

        LAST_VALUE(lat, TRUE) OVER w AS lat,
        LAST_VALUE(lon, TRUE) OVER w AS lon,
        LAST_VALUE(speed_kph, TRUE) OVER w AS speed_kph,
        engine_rpm,
        engine_load_pct,
        LAST_VALUE(coolant_temp_c, TRUE) OVER w AS coolant_temp_c,
        oil_pressure_kpa,
        transmission_temp_c,
        battery_v,
        LAST_VALUE(fuel_level_pct, TRUE) OVER w AS fuel_level_pct,
        ignition_on,
        odometer_km,
        brake_pad_wear_pct,
        dq_repaired

    FROM cleaned

    WINDOW w AS (
        PARTITION BY vehicle_id
        ORDER BY reading_ts
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )
),

lit AS (
    SELECT
        f.*,
        v.capacity_tank_I,

        ROUND(
            f.fuel_level_pct * v.capacity_tank_I / 100.0,
            1
        ) AS fuel_level_l,

        (f.ignition_on = 1 AND f.speed_kph < 5) AS is_idle

    FROM filled f

    JOIN fleet_catalog.silver.stg_vehicles v
        ON v.vehicle_id = f.vehicle_id
)

SELECT
    lit.*,

    fuel_level_l - LAG(fuel_level_l) OVER w2 AS fuel_delta_l,

    (
        UNIX_TIMESTAMP(reading_ts)
        - UNIX_TIMESTAMP(LAG(reading_ts) OVER w2)
    ) / 60.0 AS gap_min,

    LAG(speed_kph) OVER w2 AS prev_speed_kph

FROM lit

WINDOW w2 AS (
    PARTITION BY vehicle_id
    ORDER BY reading_ts
);