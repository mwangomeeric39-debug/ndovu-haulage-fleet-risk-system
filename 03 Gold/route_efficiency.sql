create or replace table fleet_catalog.gold.route_efficiency as

select
    f.route_id,
    r.route_name,
    r.corridor,
    r.terrain_index,
    f.make_model,
    count(*) as trips,
    round(sum(f.distance_km)) as km,
    round(avg(f.burn_l_per_100km), 2) as avg_burn_l_per_100km,
    round(percentile_approx(f.burn_l_per_100km, 0.9),2) as p90_burn_l_per_100km,
    round(sum(f.idle_minutes) / (sum(f.duration_h) * 60.0),3) as idle_pct,
    round(avg(if(f.is_sla_breach, 1.0, 0.0)),3) as sla_breach_rate,
    sum(f.sla_penalty_usd) as sla_penalty_usd,
    sum(if(f.is_breakdown, 1, 0)) as breakdowns,
    sum(f.fuel_loss_usd) as fuel_loss_usd
from fleet_catalog.gold.fact_trip f
join fleet_catalog.gold.dim_route r
    on r.route_id = f.route_id
group by
    f.route_id,
    r.route_name,
    r.corridor,
    r.terrain_index,
    f.make_model;
