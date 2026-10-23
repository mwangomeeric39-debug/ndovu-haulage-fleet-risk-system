create or replace table fleet_catalog.silver.stg_vehicles as 

select vehicle_id,
upper(trim(reg_no)) as reg_no,
make,
model,
concat(make,' ',model) as make_model,
vehicle_class,
try_cast(Year as INT) as model_year,
try_cast(tank_capacity_l as int) as capacity_tank_I,
upper(depot) as depot

from fleet_catalog.bronze.vehicles
where vehicle_id is not null