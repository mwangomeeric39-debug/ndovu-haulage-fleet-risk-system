create or replace table fleet_catalog.gold.dim_vehicle as

select
    vehicle_id,
    reg_no,
    make,
    model,
    concat(make, ' ', model) as make_model,
    vehicle_class,
    model_year,
    2026 - model_year as age_years,
    capacity_tank_I as tank_capacity_l,
    depot

from fleet_catalog.silver.stg_vehicles;