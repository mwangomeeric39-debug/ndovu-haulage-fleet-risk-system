CREATE OR REPLACE VIEW fleet_catalog.risk.fuel_alert_queue AS

SELECT
    CONCAT('FUEL|', e.event_id) AS alert_key,
    'SIPHON_SUSPECT' AS alert_type,
    e.vehicle_id,
    v.reg_no,
    e.driver_id,
    d.driver_name,
    e.event_ts AS event_ts,
    e.litres_lost AS litres,
    e.usd_lost AS usd_at_risk,
    e.location_type AS detail

FROM fleet_catalog.gold.fact_fuel_event e
JOIN fleet_catalog.gold.dim_vehicle v
  ON v.vehicle_id = e.vehicle_id
LEFT JOIN fleet_catalog.gold.dim_driver d
  ON d.driver_id = e.driver_id

WHERE e.event_ts >= (
    SELECT MAX(reading_ts) FROM fleet_catalog.silver.stg_telemetry) - INTERVAL 7 DAYS

AND NOT EXISTS (
    SELECT 1
    FROM fleet_catalog.risk.alert_log a
    WHERE a.alert_key = CONCAT('FUEL|', e.event_id)
      AND a.alert_type = 'FUEL_ALERT')

UNION ALL

SELECT
    CONCAT('TXN|', f.txn_id) AS alert_key,
    'FUEL_CARD_OVERBILLING' AS alert_type,
    f.vehicle_id,
    v.reg_no,
    f.driver_id,
    d.driver_name,
    f.txn_ts AS event_ts,
    f.discrepancy_l AS litres,
    ROUND(f.discrepancy_l * f.unit_price_usd) AS usd_at_risk,
    CONCAT(
        'Billed ', CAST(f.litres_billed AS STRING),
        ' L, tank gained ',
        CAST(f.litres_in_tank_sensor AS STRING), ' L') AS detail

FROM fleet_catalog.gold.fact_fuel_txn f
JOIN fleet_catalog.gold.dim_vehicle v
  ON v.vehicle_id = f.vehicle_id
LEFT JOIN fleet_catalog.gold.dim_driver d
  ON d.driver_id = f.driver_id

WHERE f.is_overbilled
  AND f.txn_ts >= (
      SELECT MAX(reading_ts) FROM fleet_catalog.silver.stg_telemetry) - INTERVAL 7 DAYS

AND NOT EXISTS (
    SELECT 1
    FROM fleet_catalog.risk.alert_log a
    WHERE a.alert_key = CONCAT('TXN|', f.txn_id)
      AND a.alert_type = 'FUEL_ALERT');