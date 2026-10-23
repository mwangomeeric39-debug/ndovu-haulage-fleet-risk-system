create or replace table fleet_catalog.gold.fact_maintenance as

with sched as (
    select
        avg(total_cost_usd) as avg_sched_cost
    from fleet_catalog.silver.stg_maintenance_orders
    where wo_type = 'Scheduled')

select
    m.wo_id,
    m.vehicle_id,
    m.wo_type,
    m.wo_type = 'Emergency' as is_emergency,
    cast(m.opened_ts as date) as opened_date,
    m.opened_ts,
    m.closed_ts,
    round(m.downtime_hours, 1) as downtime_hours,
    m.workshop,
    m.root_cause,
    m.parts_used,
    m.parts_cost_usd,
    m.labour_cost_usd,
    m.recovery_cost_usd,
    m.total_cost_usd,
    round(m.total_cost_usd / (select avg_sched_cost from sched),1) as cost_multiple_vs_scheduled,
    t.trip_id as stranded_trip_id,
    t.cargo_type as stranded_cargo,
    t.cargo_value_usd as stranded_cargo_value_usd
from fleet_catalog.silver.stg_maintenance_orders m
left join fleet_catalog.silver.stg_trips t
    on t.vehicle_id = m.vehicle_id
   and t.trip_status = 'Breakdown'
   and m.wo_type = 'Emergency'
   and m.opened_ts between t.actual_start_ts and t.actual_end_ts;