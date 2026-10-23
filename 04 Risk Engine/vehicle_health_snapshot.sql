CREATE OR REPLACE TABLE fleet_catalog.risk.vehicle_health_snapshot AS

WITH bounds AS (
    SELECT MAX(reading_ts) AS max_ts
    FROM fleet_catalog.silver.stg_telemetry
),

spine AS (
    SELECT EXPLODE(
        SEQUENCE(
            TIMESTAMP'2026-07-04 00:00:00',
            DATE_TRUNC('HOUR', (SELECT max_ts FROM bounds)),
            INTERVAL 12 HOURS)) AS snapshot_ts

    UNION

    SELECT DATE_TRUNC('HOUR', max_ts)
    FROM bounds),

grid AS (
    SELECT
        v.vehicle_id,
        s.snapshot_ts
    FROM fleet_catalog.silver.stg_vehicles v
    CROSS JOIN spine s),

feat AS (
    SELECT
        g.vehicle_id,
        g.snapshot_ts,

        -- Cooling system
        MAX(
            IF(t.reading_ts > g.snapshot_ts - INTERVAL 24 HOURS,
                t.coolant_temp_c,
                NULL)) AS coolant_max_24h,

        AVG(IF(t.reading_ts > g.snapshot_ts - INTERVAL 24 HOURS,
                t.coolant_temp_c,
                NULL)) AS coolant_avg_24h,

        AVG(IF(t.reading_ts <= g.snapshot_ts - INTERVAL 24 HOURS,
                t.coolant_temp_c,
                NULL)) AS coolant_avg_prev48h,

        -- Lubrication system
        MIN(IF(t.reading_ts > g.snapshot_ts - INTERVAL 24 HOURS
                AND t.engine_rpm > 600,
                t.oil_pressure_kpa,
                NULL)) AS oil_min_24h,

        AVG(IF(t.reading_ts > g.snapshot_ts - INTERVAL 24 HOURS
                AND t.engine_rpm > 600,
                t.oil_pressure_kpa,
                NULL)) AS oil_avg_24h,

        AVG(IF(t.reading_ts <= g.snapshot_ts - INTERVAL 24 HOURS
                AND t.engine_rpm > 600,
                t.oil_pressure_kpa,
                NULL)) AS oil_avg_prev48h,

        -- Transmission system
        MAX(IF(t.reading_ts > g.snapshot_ts - INTERVAL 24 HOURS,
                t.transmission_temp_c,
                NULL)) AS trans_max_24h,

        AVG(IF(t.reading_ts > g.snapshot_ts - INTERVAL 24 HOURS,
                t.transmission_temp_c,
                NULL)) AS trans_avg_24h,

        AVG(IF(t.reading_ts <= g.snapshot_ts - INTERVAL 24 HOURS,
                t.transmission_temp_c,
                NULL)) AS trans_avg_prev48h,

        -- Engine load and electrical system
        AVG(IF(t.reading_ts > g.snapshot_ts - INTERVAL 24 HOURS,
                t.engine_load_pct,
                NULL)) AS load_avg_24h,

        MIN(IF(t.reading_ts > g.snapshot_ts - INTERVAL 24 HOURS,
                t.battery_v,
                NULL)) AS battery_min_24h,

        -- Latest brake wear reading in the 72-hour join window
        MAX_BY(t.brake_pad_wear_pct, t.reading_ts)
            AS brake_wear_pct,

        -- Assumes one telemetry reading every 10 minutes
        SUM(IF(t.reading_ts > g.snapshot_ts - INTERVAL 24 HOURS,
                1,
                0)) * 10 / 60.0 AS engine_hours_24h

    FROM grid g

    LEFT JOIN fleet_catalog.silver.stg_telemetry t
        ON t.vehicle_id = g.vehicle_id
        AND t.ignition_on = 1
        AND t.reading_ts > g.snapshot_ts - INTERVAL 72 HOURS
        AND t.reading_ts <= g.snapshot_ts
    GROUP BY
        g.vehicle_id,
        g.snapshot_ts),

dtc AS (
    SELECT
        g.vehicle_id,
        g.snapshot_ts,

        COUNT(DISTINCT IF(
                e.severity = 'Critical',
                e.dtc_code,
                NULL)) AS active_critical_codes,

        COUNT(DISTINCT IF(
                e.severity = 'High',
                e.dtc_code,
                NULL)) AS active_high_codes,

        COUNT(DISTINCT IF(
                e.severity = 'Medium',
                e.dtc_code,
                NULL)) AS active_medium_codes

    FROM grid g
    LEFT JOIN fleet_catalog.silver.stg_dtc_events e
        ON e.vehicle_id = g.vehicle_id
        AND e.raised_ts <= g.snapshot_ts
        AND (e.cleared_ts IS NULL OR e.cleared_ts > g.snapshot_ts)

    GROUP BY
        g.vehicle_id,
        g.snapshot_ts),

svc AS (
    SELECT
        g.vehicle_id,
        g.snapshot_ts,
        MAX(m.closed_ts) AS last_service_ts
    FROM grid g
    LEFT JOIN fleet_catalog.silver.stg_maintenance_orders m
        ON m.vehicle_id = g.vehicle_id
        AND m.wo_type = 'Scheduled'
        AND m.closed_ts <= g.snapshot_ts

    GROUP BY
        g.vehicle_id,
        g.snapshot_ts),

lbl AS (
    SELECT
        g.vehicle_id,
        g.snapshot_ts,
        MAX(IF(m.wo_id IS NOT NULL,1,0)) AS fail_next_48h
    FROM grid g
    LEFT JOIN fleet_catalog.silver.stg_maintenance_orders m
        ON m.vehicle_id = g.vehicle_id
        AND m.wo_type = 'Emergency'
        AND m.opened_ts > g.snapshot_ts
        AND m.opened_ts <= g.snapshot_ts + INTERVAL 48 HOURS
    GROUP BY
        g.vehicle_id,
        g.snapshot_ts),

j AS (
    SELECT
        f.*,
        d.active_critical_codes,
        d.active_high_codes,
        d.active_medium_codes,
        DATEDIFF(f.snapshot_ts, s.last_service_ts) AS days_since_service,
        f.coolant_avg_24h - f.coolant_avg_prev48h AS coolant_trend,
        f.oil_avg_prev48h - f.oil_avg_24h AS oil_drop,
        f.trans_avg_24h - f.trans_avg_prev48h AS trans_trend,
        IF(f.snapshot_ts + INTERVAL 48 HOURS <= (SELECT max_ts FROM bounds),l.fail_next_48h,NULL) AS fail_next_48h

    FROM feat f
    JOIN dtc d
        USING (vehicle_id, snapshot_ts)
    JOIN svc s
        USING (vehicle_id, snapshot_ts)
    JOIN lbl l
        USING (vehicle_id, snapshot_ts)),

p AS (
    SELECT
        j.*,

        -- Cooling penalties
        CASE
            WHEN coolant_max_24h > 105 THEN 35
            WHEN coolant_max_24h > 101 THEN 15
            WHEN coolant_max_24h > 98 THEN 5
            ELSE 0
        END
        + IF(coolant_trend > 4, 8, 0)
            AS pen_cooling,

        -- Lubrication penalties
        CASE
            WHEN oil_min_24h < 250 THEN 35
            WHEN oil_min_24h < 300 THEN 18
            WHEN oil_min_24h < 330 THEN 6
            ELSE 0
        END
        + IF(oil_drop > 25, 8, 0)
            AS pen_oil,

        -- Transmission penalties
        CASE
            WHEN trans_max_24h > 120 THEN 40
            WHEN trans_max_24h > 110 THEN 25
            WHEN trans_max_24h > 104 THEN 8
            ELSE 0
        END
        + IF(trans_trend > 5, 8, 0)
            AS pen_transmission,

        -- Brake penalties
        CASE
            WHEN brake_wear_pct >= 90 THEN 30
            WHEN brake_wear_pct >= 80 THEN 15
            WHEN brake_wear_pct >= 70 THEN 6
            ELSE 0
        END AS pen_brakes,

        -- Electrical penalties
        IF(battery_min_24h < 24.5,8,0) AS pen_electrical,

        -- Diagnostic trouble code penalties
        LEAST(active_critical_codes * 25, 50)
        + LEAST(active_high_codes * 12, 24)
        + LEAST(active_medium_codes * 3, 6)
            AS pen_dtc,

        -- Scheduled maintenance penalties
        IF(days_since_service > 35,8,0) AS pen_service_overdue

    FROM j)

SELECT
    p.*,

    -- Overall health score, bounded at zero
    GREATEST(
        0,
        100
        - pen_cooling
        - pen_oil
        - pen_transmission
        - pen_brakes
        - pen_electrical
        - pen_dtc
        - pen_service_overdue
    ) AS health_score,

    -- Health classification
    CASE
        WHEN
            100
            - pen_cooling
            - pen_oil
            - pen_transmission
            - pen_brakes
            - pen_electrical
            - pen_dtc
            - pen_service_overdue >= 80
            THEN 'GREEN'

        WHEN
            100
            - pen_cooling
            - pen_oil
            - pen_transmission
            - pen_brakes
            - pen_electrical
            - pen_dtc
            - pen_service_overdue >= 65
            THEN 'AMBER'

        WHEN
            100
            - pen_cooling
            - pen_oil
            - pen_transmission
            - pen_brakes
            - pen_electrical
            - pen_dtc
            - pen_service_overdue >= 50
            THEN 'ORANGE'

        ELSE 'RED'
    END AS health_band,

    -- Identify the subsystem with the strongest penalty
    CASE
        WHEN
            pen_transmission >= GREATEST(
                pen_cooling,
                pen_oil,
                pen_brakes,
                pen_electrical
            )
            AND pen_transmission > 0
            THEN 'Transmission'

        WHEN
            pen_cooling >= GREATEST(
                pen_oil,
                pen_brakes,
                pen_electrical
            )
            AND pen_cooling > 0
            THEN 'Cooling'

        WHEN
            pen_oil >= GREATEST(
                pen_brakes,
                pen_electrical
            )
            AND pen_oil > 0
            THEN 'Lubrication'

        WHEN
            pen_brakes >= pen_electrical
            AND pen_brakes > 0
            THEN 'Brakes'

        WHEN pen_electrical > 0
            THEN 'Electrical'

        ELSE 'None'
    END AS suspect_system

FROM p;