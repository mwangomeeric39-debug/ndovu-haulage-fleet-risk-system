CREATE OR REPLACE TABLE fleet_catalog.silver.stg_fuel_txn AS

WITH typed AS (
    SELECT
        txn_id,
        REPLACE(UPPER(TRIM(vehicle_reg)), ' ', '') AS reg_key,
        driver_card_id AS driver_id,
        TRY_CAST(txn_ts AS TIMESTAMP) AS txn_ts,
        station_name,
        TRY_CAST(litres AS DOUBLE) AS litres,
        TRY_CAST(unit_price_usd AS DOUBLE) AS unit_price_usd,
        TRY_CAST(amount_usd AS DOUBLE) AS amount_usd,
        TRY_CAST(odometer_reported_km AS DOUBLE) AS odometer_reported_km,
        TRY_CAST(invoice_received_ts AS TIMESTAMP) AS invoice_received_ts
    FROM fleet_catalog.bronze.fuel_transactions
    WHERE txn_id IS NOT NULL)

SELECT
    t.txn_id,
    v.vehicle_id,
    t.driver_id,
    tr.trip_id,
    t.txn_ts,
    t.station_name,
    t.litres,
    t.unit_price_usd,
    t.amount_usd,
    t.odometer_reported_km,
    t.invoice_received_ts
FROM typed t

JOIN fleet_catalog.silver.stg_vehicles v
ON v.reg_no = t.reg_key

LEFT JOIN fleet_catalog.silver.stg_trips tr
ON tr.vehicle_id = v.vehicle_id
AND t.txn_ts BETWEEN tr.actual_start_ts - INTERVAL 60 MINUTES AND tr.actual_end_ts;