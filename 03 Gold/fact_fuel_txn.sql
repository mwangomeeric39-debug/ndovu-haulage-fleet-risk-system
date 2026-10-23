create or replace table fleet_catalog.gold.fact_fuel_txn as

with ev as (
    select
        vehicle_id,
        reading_ts as ts,
        fuel_level_l as lvl,
        cast(null as string) as txn_id,
        0 as is_txn
    from fleet_catalog.silver.stg_telemetry
    union all
    select
        vehicle_id,
        txn_ts as ts,
        cast(null as double) as lvl,
        txn_id,
        1 as is_txn
    from fleet_catalog.silver.stg_fuel_txn),

w as (
    select
        vehicle_id,
        ts,
        txn_id,
        is_txn,

        last_value(lvl, true) over (
            partition by vehicle_id
            order by ts, is_txn
            rows between unbounded preceding and current row) as lvl_before,

        first_value(lvl, true) over (
            partition by vehicle_id
            order by ts, is_txn
            rows between current row and unbounded following) as lvl_after
    from ev)

select
    f.txn_id,
    f.vehicle_id,
    f.driver_id,
    f.trip_id,
    cast(f.txn_ts as date) as txn_date,
    f.txn_ts,
    f.station_name,

    f.litres as litres_billed,
    f.unit_price_usd,
    f.amount_usd,
    round(w.lvl_after - w.lvl_before, 1) as litres_in_tank_sensor,

    round(f.litres - (w.lvl_after - w.lvl_before),1) as discrepancy_l,

    (w.lvl_before is not null
        and (f.litres - (w.lvl_after - w.lvl_before)) > greatest(20, 0.10 * f.litres)) as is_overbilled,
    
    datediff(f.invoice_received_ts, f.txn_ts) as invoice_lag_days
from fleet_catalog.silver.stg_fuel_txn f
join w
    on w.txn_id = f.txn_id
   and w.is_txn = 1;