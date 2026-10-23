create or replace table fleet_catalog.gold.fact_trip as

with px as (
    select
        avg(unit_price_usd) as fuel_price_usd
    from fleet_catalog.silver.stg_fuel_txn),

disp as (
    select
        d.trip_id,
        max(case e.severity when 'Critical' then 2 when 'High' then 1 else 0 end) as worst_sev
    from fleet_catalog.silver.stg_dispatch d
    left join fleet_catalog.silver.stg_dtc_events e
        on e.vehicle_id = d.vehicle_id
       and e.severity in ('Critical', 'High')
       and e.raised_ts <= d.dispatched_ts
       and (e.cleared_ts is null or e.cleared_ts > d.dispatched_ts)
    group by d.trip_id),

x as (
select
        m.*,
        t.actual_start_ts,
        t.actual_end_ts,
        t.cargo_type,
        t.cargo_value_usd,
        t.sla_hours,
        t.sla_penalty_per_hour_usd,
        (unix_timestamp(t.actual_end_ts) - unix_timestamp(t.actual_start_ts)) / 3600.0 as duration_h,
        b.median_burn as expected_burn_l_per_100km,
        b.robust_sd,
        (m.burn_l_per_100km - b.median_burn)/ b.robust_sd as burn_z,
        coalesce(dp.worst_sev, 0) as worst_sev_at_dispatch
    from fleet_catalog.gold.int_trip_metrics m
    join fleet_catalog.silver.stg_trips t
        on t.trip_id = m.trip_id
    left join fleet_catalog.gold.ref_burn_baseline b
        on b.route_id = m.route_id
       and b.make_model = m.make_model
       and b.load_band = m.load_band
    left join disp dp
        on dp.trip_id = m.trip_id),

y as (
    select
        x.*,
        greatest(duration_h - sla_hours, 0) as sla_breach_h,
        idle_minutes / (duration_h * 60.0) as idle_pct,
        (burn_z >= 3
            and burn_l_per_100km > expected_burn_l_per_100km * 1.08
            and trip_status = 'Completed') as is_high_burn
    from x)

select
    trip_id,
    vehicle_id,
    driver_id,
    route_id,
    cast(actual_start_ts as date) as trip_date,
    actual_start_ts,
    actual_end_ts,
    make_model,
    cargo_type,
    cargo_value_usd,
    load_pct,
    trip_status,
    trip_status = 'Breakdown' as is_breakdown,
    distance_km,
    round(duration_h, 2) as duration_h,
    sla_hours,
    round(sla_breach_h, 2) as sla_breach_h,
    sla_breach_h > 0 as is_sla_breach,

    round(
        least(
            sla_breach_h * sla_penalty_per_hour_usd,
            0.3 * cargo_value_usd),0) as sla_penalty_usd,
    idle_minutes,
    round(idle_pct, 3) as idle_pct,
    round(idle_minutes / 60.0 * 3.0, 1) as idle_fuel_l,
    round(fuel_consumed_l, 1) as fuel_consumed_l,
    round(siphon_l, 1) as siphon_l,
    round(burn_l_per_100km, 2) as burn_l_per_100km,
    round(expected_burn_l_per_100km, 2)
        as expected_burn_l_per_100km,
    round(burn_z, 2) as burn_z,
    is_high_burn,
    siphon_l > 0 as is_siphon,
    idle_pct >= 0.20 as is_excess_idle,
    
    round(if(is_high_burn,
            greatest(fuel_consumed_l - expected_burn_l_per_100km * distance_km / 100,0),0),1) as excess_burn_l,
    round((siphon_l + if(is_high_burn,greatest(fuel_consumed_l
                    - expected_burn_l_per_100km * distance_km / 100,0),0)) * (select fuel_price_usd from px),0) 
                    as fuel_loss_usd,

    worst_sev_at_dispatch >= 1 as dispatched_with_fault,
    case worst_sev_at_dispatch
        when 2 then 'Critical'
        when 1 then 'High'
        else 'None'
    end as fault_severity_at_dispatch,

    avg_moving_speed_kph,
    max_coolant_c,
    max_trans_c,
    min_oil_kpa

from y;