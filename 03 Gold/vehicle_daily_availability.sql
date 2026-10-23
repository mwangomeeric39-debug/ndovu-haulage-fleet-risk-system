create or replace table fleet_catalog.gold.vehicle_daily_availability as

with iv as (
    select
        vehicle_id,
        'TRIP' as kind,
        actual_start_ts as s,
        actual_end_ts as e
    from fleet_catalog.silver.stg_trips
    union all
    select
        vehicle_id,
        if(wo_type = 'Emergency', 'EMERGENCY', 'SCHEDULED') as kind,
        opened_ts as s,
        closed_ts as e
    from fleet_catalog.silver.stg_maintenance_orders),

dd as (
    select
        vehicle_id,
        kind,
        s,
        e,
        explode(sequence(cast(s as date),cast(e as date),interval 1 day)) as d
    from iv
    where s is not null
      and e is not null
      and e > s),

ov as (
    select
        vehicle_id,
        d as date_key,
        kind,
        greatest(0,
            unix_timestamp(
                least(e, cast(d + interval 1 day as timestamp)))
            - unix_timestamp(
                greatest(s, cast(d as timestamp)))) / 3600.0 as hrs
    from dd),

agg as (
    select
        vehicle_id,
        date_key,
        sum(if(kind = 'TRIP', hrs, 0)) as trip_hours,
        sum(if(kind = 'SCHEDULED', hrs, 0)) as scheduled_workshop_hours,
        sum(if(kind = 'EMERGENCY', hrs, 0)) as emergency_downtime_hours
    from ov
    group by vehicle_id, date_key)

select
    v.vehicle_id,
    d.date_key,
    round(coalesce(a.trip_hours, 0), 2) as trip_hours,
    round(coalesce(a.scheduled_workshop_hours, 0), 2) as scheduled_workshop_hours,
    round(coalesce(a.emergency_downtime_hours, 0), 2) as emergency_downtime_hours,

    round(
        greatest(24
            - coalesce(a.scheduled_workshop_hours, 0)
            - coalesce(a.emergency_downtime_hours, 0),
            0),2) as available_hours,

    round(
        greatest(24
            - coalesce(a.scheduled_workshop_hours, 0)
            - coalesce(a.emergency_downtime_hours, 0),
            0) / 24.0,4) as availability_pct

from fleet_catalog.gold.dim_vehicle v
cross join (
    select date_key
    from fleet_catalog.gold.dim_date
    where date_key between date'2026-07-01' and date'2026-09-30') d
left join agg a
    on a.vehicle_id = v.vehicle_id
   and a.date_key = d.date_key;