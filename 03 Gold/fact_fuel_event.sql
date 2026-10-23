create or replace table fleet_catalog.gold.fact_fuel_event as

with px as (
    select
        avg(unit_price_usd) as p
    from fleet_catalog.silver.stg_fuel_txn)

select
    e.event_id,
    e.vehicle_id,
    t.trip_id,
    t.driver_id,
    e.event_ts,
    cast(e.event_ts as date) as event_date,
    hour(e.event_ts) as event_hour,
    round(-e.fuel_delta_l, 1) as litres_lost,
    round(-e.fuel_delta_l * (select p from px), 0) as usd_lost,
    e.lat,
    e.lon,

    if(
        e.trip_id is null,
        'Parked after delivery',
        'Roadside stop') as location_type

from fleet_catalog.silver.stg_fuel_events e
left join fleet_catalog.silver.stg_trips t
    on t.vehicle_id = e.vehicle_id
   and e.event_ts between t.actual_start_ts
                      and t.actual_end_ts + interval 6 hours

where e.event_type = 'SIPHON_SUSPECT';