create or replace table fleet_catalog.gold.ref_burn_baseline as

with base as (
    select
        route_id,
        make_model,
        load_band,
        burn_l_per_100km
    from fleet_catalog.gold.int_trip_metrics
    where trip_status = 'Completed'
      and distance_km >= 100
      and burn_l_per_100km between 10 and 80),

med as (
    select
        route_id,
        make_model,
        load_band,
        percentile_approx(burn_l_per_100km, 0.5) as median_burn,
        count(*) as n_trips
    from base
    group by
        route_id,
        make_model,
        load_band),

dev as (
    select
        b.route_id,
        b.make_model,
        b.load_band,
        abs(b.burn_l_per_100km - m.median_burn) as abs_dev

    from base b
    join med m
        on b.route_id = m.route_id
       and b.make_model = m.make_model
       and b.load_band = m.load_band)

select
    m.route_id,
    m.make_model,
    m.load_band,
    m.median_burn,
    m.n_trips,
    greatest(percentile_approx(d.abs_dev, 0.5) * 1.4826, 0.5) as robust_sd
from med m
join dev d
    on m.route_id = d.route_id
   and m.make_model = d.make_model
   and m.load_band = d.load_band
group by
    m.route_id,
    m.make_model,
    m.load_band,
    m.median_burn,
    m.n_trips;