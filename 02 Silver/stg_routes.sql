create or replace table fleet_catalog.silver.stg_routes as 

select route_id,
route_name,
origin,
initcap(destination) as destination,
try_cast(distance_km as double) as distance_km,
try_cast(terrain_index as double) as terrain_index,
try_cast(elevation_gain_m as double) as elevation_gain_m,
corridor

from fleet_catalog.bronze.routes

where route_id is not null