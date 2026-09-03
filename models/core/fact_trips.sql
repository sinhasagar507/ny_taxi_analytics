{{ config(
    materialized='table',
    partition_by={"field": "pickup_datetime", "data_type": "timestamp",
                  "granularity": "month"},
    cluster_by=["pickup_locationid", "dropoff_locationid"]
) }}

with green_tripdata as (
    select *,
           'Green' as service_type
    from {{ ref('stg_green_taxi_data') }}
),
yellow_tripdata as (
    select *,
           'Yellow' as service_type
    from {{ ref('stg_yellow_taxi_data') }}
),
trips_unioned as (
    select * from green_tripdata
    union all
    select * from yellow_tripdata
),
dim_zones as (
    select *
    from {{ ref('dim_zones') }}
    where borough != 'Unknown'
),
climate_data as (
    select *
    from {{ ref('stg_climate_data') }}
)

select
    tu.tripid,
    tu.vendorid, 
    tu.service_type,
    tu.ratecodeid, 
    tu.pickup_locationid, 
    pz.borough as pickup_borough, 
    pz.zone as pickup_zone, 
    tu.dropoff_locationid,
    dz.borough as dropoff_borough, 
    dz.zone as dropoff_zone,  
    tu.pickup_datetime, 
    tu.pickup_date,
    tu.dropoff_datetime, 
    tu.store_and_fwd_flag, 
    tu.passenger_count, 
    tu.trip_distance, 
    -- tu.trip_type, 
    tu.fare_amount, 
    tu.extra, 
    tu.mta_tax, 
    tu.tip_amount, 
    tu.tolls_amount, 
    -- tu.ehail_fee, 
    tu.improvement_surcharge, 
    tu.total_amount, 
    tu.payment_type, 
    tu.payment_type_description,
    cd.*  -- This will include all columns from climate_data
from trips_unioned tu
inner join dim_zones pz
    on tu.pickup_locationid = pz.locationid
inner join dim_zones dz
    on tu.dropoff_locationid = dz.locationid
left join climate_data cd
    on tu.pickup_date = cd.climate_date

-- {% if var('is_test_run', default=true) %}
--   limit 1050
-- {% endif %}
