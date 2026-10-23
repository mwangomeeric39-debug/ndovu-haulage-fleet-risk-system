create or replace table fleet_catalog.gold.dim_route as

select
    route_id,
    route_name,
    origin,
    destination,
    distance_km,
    terrain_index,
    elevation_gain_m,
    corridor

from fleet_catalog.silver.stg_routes