create or replace table fleet_catalog.gold.dim_date as

select
    d as date_key,
    year(d) as year,
    month(d) as month_num,
    date_format(d, 'MMM') as month_name,
    weekofyear(d) as week_num,
    date_format(d, 'EEEE') as day_name,
    dayofweek(d) in (1, 7) as is_weekend

from (select explode(
        sequence(date'2026-07-01', date'2026-12-31',interval 1 day)) as d);