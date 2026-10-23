create or replace table fleet_catalog.gold.dim_driver as

select
    driver_id,
    upper(trim(driver_name)) as driver_name,
    try_cast(years_experience as int) as years_experience,
    upper(trim(licence_class)) as licence_class

from fleet_catalog.silver.stg_drivers

where driver_id is not null;