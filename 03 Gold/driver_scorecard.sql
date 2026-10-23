create or replace table fleet_catalog.gold.driver_scorecard as

with tr as (
    select
        driver_id,
        count(*) as trips,
        sum(distance_km) as km,
        avg(burn_z) as avg_burn_z,
        sum(idle_minutes) / (sum(duration_h) * 60.0) as idle_pct,
        sum(if(is_high_burn, 1, 0)) as high_burn_trips,
        sum(if(is_excess_idle, 1, 0)) as excess_idle_trips,
        sum(fuel_loss_usd) as fuel_loss_usd
    from fleet_catalog.gold.fact_trip
    group by driver_id),

ev as (
    select
        driver_id,
        count(*) as siphon_events,
        sum(litres_lost) as siphon_l
    from fleet_catalog.gold.fact_fuel_event
    group by driver_id),

tx as (
    select
        driver_id,
        count(*) as fuel_txns,
        sum(if(is_overbilled, 1, 0)) as overbilled_txns,
        sum(if(is_overbilled, discrepancy_l, 0)) as overbilled_l
    from fleet_catalog.gold.fact_fuel_txn
    group by driver_id)

select
    d.driver_id,
    d.driver_name,
    d.years_experience,
    tr.trips,
    round(tr.km) as km,
    round(tr.avg_burn_z, 2) as avg_burn_z,
    round(tr.idle_pct, 3) as idle_pct,
    tr.high_burn_trips,
    tr.excess_idle_trips,
    coalesce(ev.siphon_events, 0) as siphon_events,
    round(coalesce(ev.siphon_l, 0)) as siphon_l,
    coalesce(tx.overbilled_txns, 0) as overbilled_txns,
    round(coalesce(tx.overbilled_l, 0)) as overbilled_l,
    round(tr.fuel_loss_usd) as fuel_loss_usd,

    least(
        100,
        coalesce(ev.siphon_events, 0) * 10
        + coalesce(tx.overbilled_txns, 0) * 5
        + tr.high_burn_trips * 2
        + tr.excess_idle_trips) as fuel_risk_score,

    case
        when coalesce(ev.siphon_events, 0) >= 2
          or coalesce(tx.overbilled_txns, 0) >= 3
            then 'Investigate'

        when coalesce(ev.siphon_events, 0) = 1
          or coalesce(tx.overbilled_txns, 0) >= 1
          or tr.excess_idle_trips >= 10
          or tr.high_burn_trips >= 10
            then 'Watch'

        else 'Normal'
    end as fuel_risk_band

from fleet_catalog.gold.dim_driver d
join tr
    on tr.driver_id = d.driver_id
left join ev
    on ev.driver_id = d.driver_id
left join tx
    on tx.driver_id = d.driver_id;