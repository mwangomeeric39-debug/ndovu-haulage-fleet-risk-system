create or replace table fleet_catalog.gold.kpi_daily_fleet as

with t as (
    select
        trip_date as date_key,
        count(*) as trips,
        sum(distance_km) as km,
        sum(if(is_breakdown, 1, 0)) as breakdowns,
        sum(if(is_sla_breach, 1, 0)) as sla_breaches,
        sum(sla_penalty_usd) as sla_penalty_usd,
        sum(fuel_loss_usd) as fuel_loss_usd,
        sum(if(dispatched_with_fault, 1, 0))
            as dispatches_with_open_fault
    from fleet_catalog.gold.fact_trip
    group by trip_date),

a as (
    select
        date_key,
        avg(availability_pct) as fleet_availability_pct
    from fleet_catalog.gold.vehicle_daily_availability
    group by date_key),

fz as (
    select
        txn_date as date_key,
        sum(amount_usd) as fuel_spend_usd,
        sum(
            if(is_overbilled, discrepancy_l * unit_price_usd, 0)
        ) as fuel_overbilled_usd
    from fleet_catalog.gold.fact_fuel_txn
    group by txn_date),

m as (
    select
        opened_date as date_key,
        sum(total_cost_usd) as maintenance_cost_usd,
        sum(if(is_emergency, total_cost_usd, 0))
            as emergency_cost_usd
    from fleet_catalog.gold.fact_maintenance
    group by opened_date)

select
    d.date_key,
    coalesce(t.trips, 0) as trips,
    round(coalesce(t.km, 0)) as km,
    coalesce(t.breakdowns, 0) as breakdowns,
    coalesce(t.sla_breaches, 0) as sla_breaches,
    coalesce(t.sla_penalty_usd, 0) as sla_penalty_usd,
    coalesce(t.fuel_loss_usd, 0) as fuel_loss_usd,
    round(coalesce(fz.fuel_spend_usd, 0)) as fuel_spend_usd,
    round(coalesce(fz.fuel_overbilled_usd, 0)) as fuel_overbilled_usd,
    coalesce(t.dispatches_with_open_fault, 0) as dispatches_with_open_fault,
    round(a.fleet_availability_pct, 4) as fleet_availability_pct,
    coalesce(m.maintenance_cost_usd, 0) as maintenance_cost_usd,
    coalesce(m.emergency_cost_usd, 0) as emergency_cost_usd

from fleet_catalog.gold.dim_date d
left join t
    on t.date_key = d.date_key
left join a
    on a.date_key = d.date_key
left join m
    on m.date_key = d.date_key
left join fz
    on fz.date_key = d.date_key
where d.date_key between date'2026-07-01' and date'2026-09-30';