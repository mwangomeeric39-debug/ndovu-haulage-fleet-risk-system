CREATE OR REPLACE TABLE fleet_catalog.silver.stg_dq_summary AS

SELECT
    'telemetry' AS dataset,
    'raw rows in bronze' AS check_name,
    COUNT(*) AS n
FROM fleet_catalog.bronze.telemetry

UNION ALL

SELECT
    'telemetry',
    'duplicate rows removed',
    (SELECT COUNT(*) FROM fleet_catalog.bronze.telemetry)
    - (SELECT COUNT(*) FROM fleet_catalog.silver.stg_telemetry)

UNION ALL

SELECT
    'telemetry',
    'rows repaired (bad GPS / speed / coolant / null fuel)',
    SUM(dq_repaired)
FROM fleet_catalog.silver.stg_telemetry

UNION ALL

SELECT
    'fuel_txn',
    'duplicate postings removed',
    (SELECT COUNT(*) FROM fleet_catalog.bronze.fuel_transactions)
    - (SELECT COUNT(*) FROM fleet_catalog.silver.stg_fuel_txn)

UNION ALL

SELECT
    'fuel_txn',
    'transactions not matched to a vehicle',
    (SELECT COUNT(DISTINCT txn_id) FROM fleet_catalog.bronze.fuel_transactions)
    - (SELECT COUNT(*) FROM fleet_catalog.silver.stg_fuel_txn);