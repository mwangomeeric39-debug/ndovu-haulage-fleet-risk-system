create or replace table fleet_catalog.silver.stg_drivers as 

select driver_id,
initcap(trim(driver_name)) as driver_name,
try_cast(years_experience as int) as years_experience,
licence_class

from fleet_catalog.bronze.drivers
where driver_id is not null