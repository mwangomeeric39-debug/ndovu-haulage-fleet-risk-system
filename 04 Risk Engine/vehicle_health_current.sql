CREATE OR REPLACE TABLE fleet_catalog.risk.vehicle_health_current AS
WITH asof AS (
    SELECT MAX(snapshot_ts) AS ts
    FROM fleet_catalog.risk.vehicle_health_snapshot),

cur AS (
    SELECT s.*
    FROM fleet_catalog.risk.vehicle_health_snapshot s
    JOIN asof a ON s.snapshot_ts = a.ts),

worst AS (
    SELECT
        e.vehicle_id,
        e.dtc_code,
        e.description,
        e.severity,
        e.raised_ts,
        ROW_NUMBER() OVER (
            PARTITION BY e.vehicle_id
            ORDER BY
                CASE e.severity
                    WHEN 'Critical' THEN 1
                    ELSE 2
                END,
                e.raised_ts DESC) AS rn
    FROM fleet_catalog.silver.stg_dtc_events e
    JOIN asof a
      ON e.raised_ts <= a.ts
     AND (e.cleared_ts IS NULL OR e.cleared_ts > a.ts)
    WHERE e.severity IN ('Critical', 'High')),

now_trip AS (
    SELECT
        t.vehicle_id,
        t.trip_id,
        t.route_id
    FROM fleet_catalog.silver.stg_trips t
    JOIN asof a
      ON a.ts BETWEEN t.actual_start_ts AND t.actual_end_ts),

x AS (
    SELECT
        c.vehicle_id,
        v.reg_no,
        v.make_model,
        v.depot,
        c.snapshot_ts,
        c.health_score,
        c.health_band,
        COALESCE(r.failure_prob_48h, 0) AS failure_prob_48h,
        c.active_critical_codes,
        c.active_high_codes,
        w.dtc_code,
        w.description AS dtc_description,
        w.severity AS dtc_severity,

        COALESCE(
            CASE
                WHEN w.dtc_code = 'P0217' THEN 'Cooling'
                WHEN w.dtc_code = 'P0524' THEN 'Lubrication'
                WHEN w.dtc_code IN ('P0218', 'P0700', 'P0730')
                    THEN 'Transmission'
                WHEN w.dtc_code = 'C1145' THEN 'Brakes'
                WHEN w.dtc_code = 'P0562' THEN 'Electrical'
            END,
            NULLIF(c.suspect_system, 'None'),
            'None') AS suspect_system,
        c.coolant_max_24h,
        c.oil_min_24h,
        c.trans_max_24h,
        c.brake_wear_pct,
        c.days_since_service,
        nt.trip_id AS current_trip_id,
        nt.route_id AS current_route_id

    FROM cur c
    JOIN fleet_catalog.silver.stg_vehicles v
      ON v.vehicle_id = c.vehicle_id
    LEFT JOIN fleet_catalog.gold.failure_risk_score r
      ON r.vehicle_id = c.vehicle_id
     AND r.snapshot_ts = c.snapshot_ts
    LEFT JOIN worst w
      ON w.vehicle_id = c.vehicle_id
     AND w.rn = 1
    LEFT JOIN now_trip nt
      ON nt.vehicle_id = c.vehicle_id)

SELECT
    x.*,

    CASE
        WHEN health_score < 50
          OR active_critical_codes > 0
          OR failure_prob_48h >= 0.60
            THEN 'LOCK'
        WHEN health_score < 70
          OR active_high_codes > 0
          OR failure_prob_48h >= 0.35
            THEN 'RESTRICT'
        ELSE 'CLEAR'
    END AS dispatch_status,

    CONCAT_WS(
        ' | ',
        IF(
            active_critical_codes > 0,
            CONCAT('Active CRITICAL code ', dtc_code, ' - ', dtc_description),
            NULL),
        IF(
            active_critical_codes = 0 AND active_high_codes > 0,
            CONCAT('Open HIGH code ', dtc_code, ' - ', dtc_description),
            NULL),
        IF(
            health_score < 70,
            CONCAT('Health score ', CAST(health_score AS STRING),
                   '/100 (', suspect_system, ')'),
            NULL),
        IF(
            failure_prob_48h >= 0.35,
            CONCAT('Model: ',
                   CAST(ROUND(failure_prob_48h * 100) AS STRING),
                   '% breakdown risk in 48h'),
            NULL)
    ) AS reason

FROM x;
