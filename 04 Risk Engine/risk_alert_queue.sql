CREATE OR REPLACE VIEW fleet_catalog.risk.risk_alert_queue AS

WITH asof AS (
    SELECT MAX(reading_ts) AS ts
    FROM fleet_catalog.silver.stg_telemetry),

imp AS (
    SELECT
        (SELECT ROUND(AVG(total_cost_usd))
         FROM fleet_catalog.gold.fact_maintenance
         WHERE is_emergency)
        +
        (SELECT ROUND(AVG(sla_penalty_usd))
         FROM fleet_catalog.gold.fact_trip
         WHERE is_breakdown) AS breakdown_impact_usd),

q AS (

    -- MAINTENANCE RISKS
    SELECT
        CONCAT(
            'RISK|MAINT|', h.vehicle_id, '|',
            COALESCE(h.dtc_code, 'MODEL'), '|',
            DATE_FORMAT(h.snapshot_ts, 'yyyyMMdd')) AS alert_key,

        'MAINTENANCE' AS risk_type,
        IF(h.dispatch_status = 'LOCK', 'CRITICAL', 'HIGH') AS severity,
        h.vehicle_id,
        h.reg_no,
        CAST(NULL AS STRING) AS driver_id,

        CONCAT(
            'Dispatch status ', h.dispatch_status,
            ' | health ', CAST(h.health_score AS STRING), '/100',
            ' | 48h breakdown probability ',
            CAST(ROUND(h.failure_prob_48h * 100) AS STRING), '%',
            ' | suspect system ', h.suspect_system,
            ' | open code ',
            COALESCE(CONCAT(h.dtc_code, ' ', h.dtc_description), 'none'),
            ' | coolant max ', COALESCE(CAST(h.coolant_max_24h AS STRING), 'n/a'),
            ' C, oil min ', COALESCE(CAST(h.oil_min_24h AS STRING), 'n/a'),
            ' kPa, transmission max ',
            COALESCE(CAST(h.trans_max_24h AS STRING), 'n/a'),
            ' C, brake wear ',
            COALESCE(CAST(h.brake_wear_pct AS STRING), 'n/a'),
            '%, days since service ',
            COALESCE(CAST(h.days_since_service AS STRING), 'n/a')
        ) AS evidence,

        (SELECT breakdown_impact_usd FROM imp) AS potential_impact_usd,
        'Fleet manager + maintenance lead' AS suggested_owner

    FROM fleet_catalog.risk.vehicle_health_current h
    WHERE h.dispatch_status IN ('LOCK', 'RESTRICT')

    UNION ALL

    -- FUEL RISKS
    SELECT
        f.alert_key,
        'FUEL',
        IF(f.usd_at_risk >= 150, 'HIGH', 'MEDIUM'),
        f.vehicle_id,
        f.reg_no,
        f.driver_id,

        CONCAT(
            f.alert_type, ' | driver ',
            COALESCE(f.driver_name, 'unknown'),
            ' | ', CAST(f.litres AS STRING), ' L | ',
            f.detail, ' | at ', CAST(f.event_ts AS STRING)),

        f.usd_at_risk,
        'Fleet controller'

    FROM fleet_catalog.risk.fuel_alert_queue f

    UNION ALL

    -- DISPATCH RISKS
    SELECT
        CONCAT('RISK|DISP|', t.trip_id),
        'DISPATCH',
        IF(t.fault_severity_at_dispatch = 'Critical', 'CRITICAL', 'HIGH'),
        t.vehicle_id,
        v.reg_no,
        t.driver_id,

        CONCAT(
            'Trip ', t.trip_id, ' on ', r.route_name,
            ' (', CAST(t.distance_km AS STRING), ' km) was dispatched with an open ',
            t.fault_severity_at_dispatch, ' fault code | cargo ',
            t.cargo_type, ' worth USD ',
            CAST(t.cargo_value_usd AS STRING),
            ' | trip status ', t.trip_status),

        (SELECT breakdown_impact_usd FROM imp),
        'Dispatcher + fleet manager'

    FROM fleet_catalog.gold.fact_trip t
    JOIN fleet_catalog.gold.dim_vehicle v ON v.vehicle_id = t.vehicle_id
    JOIN fleet_catalog.gold.dim_route r ON r.route_id = t.route_id
    WHERE t.dispatched_with_fault
      AND t.actual_start_ts >= (
          SELECT ts FROM asof
      ) - INTERVAL 7 DAYS

    UNION ALL

    -- DELIVERY DELAY RISKS
    SELECT
        CONCAT('RISK|DELAY|', t.trip_id),
        'DELAY',
        IF(t.is_breakdown OR t.sla_penalty_usd >= 1000,'HIGH','MEDIUM'),
        t.vehicle_id,
        v.reg_no,
        t.driver_id,

        CONCAT(
            'Trip ', t.trip_id, ' on ', r.route_name,
            ' took ', CAST(t.duration_h AS STRING),
            ' h against an SLA of ', CAST(t.sla_hours AS STRING),
            ' h (late by ', CAST(t.sla_breach_h AS STRING),
            ' h) | cargo ', t.cargo_type,
            ' worth USD ', CAST(t.cargo_value_usd AS STRING),
            ' | breakdown: ',
            IF(t.is_breakdown, 'yes', 'no'),
            ' | idle share ', CAST(ROUND(t.idle_pct * 100) AS STRING), '%'),
        t.sla_penalty_usd,
        'Operations manager'

    FROM fleet_catalog.gold.fact_trip t
    JOIN fleet_catalog.gold.dim_vehicle v ON v.vehicle_id = t.vehicle_id
    JOIN fleet_catalog.gold.dim_route r ON r.route_id = t.route_id
    WHERE (t.is_breakdown OR t.sla_penalty_usd >= 300)
      AND t.actual_start_ts >= (SELECT ts FROM asof) - INTERVAL 7 DAYS)

SELECT q.*
FROM q
WHERE NOT EXISTS (
    SELECT 1
    FROM fleet_catalog.risk.alert_log a
    WHERE a.alert_key = q.alert_key
      AND a.alert_type = 'RISK_ALERT');