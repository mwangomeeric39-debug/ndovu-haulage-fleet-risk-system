create or replace table fleet_catalog.gold.int_trip_metrics as

with tel as (
    select
        trip_id,
        sum(if(is_idle, 1, 0)) * 10 as idle_minutes,
        avg(if(speed_kph >= 5, speed_kph, null)) as avg_moving_speed_kph,
        max(speed_kph) as max_speed_kph,
        max(coolant_temp_c) as max_coolant_c,
        max(transmission_temp_c) as max_trans_c,
        min(if(engine_rpm > 600, oil_pressure_kpa, null)) as min_oil_kpa,
        min_by(fuel_level_l, reading_ts) as fuel_start_l,
        max_by(fuel_level_l, reading_ts) as fuel_end_l,
        sum(if(fuel_delta_l >= 25 and gap_min <= 90, fuel_delta_l, 0)) as midtrip_refuel_l
    from fleet_catalog.silver.stg_telemetry
    where trip_id is not null
    group by trip_id),

sip as (
    select
        trip_id,
        sum(-fuel_delta_l) as siphon_l,
        count(*) as siphon_events
    from fleet_catalog.silver.stg_fuel_events
    where event_type = 'SIPHON_SUSPECT'
      and trip_id is not null
    group by trip_id)

select
    t.trip_id,
    t.vehicle_id,
    t.driver_id,
    t.route_id,
    v.make_model,
    t.trip_status,
    t.distance_km,
    t.load_pct,

    case
        when t.load_pct >= 75 then 'Heavy'
        else 'Light-Medium'
    end as load_band,

    tel.idle_minutes,
    tel.avg_moving_speed_kph,
    tel.max_speed_kph,
    tel.max_coolant_c,
    tel.max_trans_c,
    tel.min_oil_kpa,

    coalesce(sip.siphon_l, 0) as siphon_l,

    tel.fuel_start_l
        - tel.fuel_end_l
        + tel.midtrip_refuel_l
        - coalesce(sip.siphon_l, 0) as fuel_consumed_l,

      ( tel.fuel_start_l
        - tel.fuel_end_l
        + tel.midtrip_refuel_l
        - coalesce(sip.siphon_l, 0)) / t.distance_km * 100 as burn_l_per_100km

from fleet_catalog.silver.stg_trips t
join fleet_catalog.gold.dim_vehicle v
    on v.vehicle_id = t.vehicle_id
left join tel
    on tel.trip_id = t.trip_id
left join sip
    on sip.trip_id = t.trip_id;