{{ config(materialized='view') }}
 
with tripdata as 
(
  select *,
    -- The tie-break MUST be deterministic. Without an order by, BigQuery picks an
    -- arbitrary winner per (vendorid, pickup_datetime) group, and 74.4M of these groups
    -- hold rows that disagree on the zone pair. fact_trips then inner-joins dim_zones
    -- with borough != 'Unknown', so an arbitrary winner changes the mart's row count on
    -- every build. Ordering by every remaining column leaves ties only between rows that
    -- are identical, which makes the output reproducible.
    row_number() over(
      partition by vendorid, tpep_pickup_datetime
      order by tpep_dropoff_datetime, pulocationid, dolocationid, payment_type,
               ratecodeid, store_and_fwd_flag, passenger_count, trip_distance,
               fare_amount, extra, mta_tax, tip_amount, tolls_amount,
               improvement_surcharge, total_amount, congestion_surcharge, airport_fee
    ) as rn
  from {{ source('staging','yellow_taxi_external_table') }}
  where vendorid is not null 
    and cast(tpep_pickup_datetime as date) between '2015-01-01' and '2016-12-31'
)
select
   -- identifiers
    {{ dbt_utils.generate_surrogate_key(['vendorid', 'tpep_pickup_datetime']) }} as tripid,    
    {{ dbt.safe_cast("vendorid", api.Column.translate_type("integer")) }} as vendorid,
    {{ dbt.safe_cast("ratecodeid", api.Column.translate_type("integer")) }} as ratecodeid,
    {{ dbt.safe_cast("pulocationid", api.Column.translate_type("integer")) }} as pickup_locationid,
    {{ dbt.safe_cast("dolocationid", api.Column.translate_type("integer")) }} as dropoff_locationid,

    -- timestamps
    cast(tpep_pickup_datetime as timestamp) as pickup_datetime,
    cast(tpep_pickup_datetime as date) as pickup_date,  -- New column extracted as date
    cast(tpep_dropoff_datetime as timestamp) as dropoff_datetime,
    
    -- trip info
    store_and_fwd_flag,
    {{ dbt.safe_cast("passenger_count", api.Column.translate_type("integer")) }} as passenger_count,
    cast(trip_distance as numeric) as trip_distance,
    -- yellow cabs are always street-hail
    -- 1.0 as trip_type,
    
    -- payment info
    cast(fare_amount as numeric) as fare_amount,
    cast(extra as numeric) as extra,
    cast(mta_tax as numeric) as mta_tax,
    cast(tip_amount as numeric) as tip_amount,
    cast(tolls_amount as numeric) as tolls_amount,
    -- cast(0 as numeric) as ehail_fee,
    cast(improvement_surcharge as numeric) as improvement_surcharge,
    cast(total_amount as numeric) as total_amount,
    coalesce({{ dbt.safe_cast("payment_type", api.Column.translate_type("integer")) }},0) as payment_type,
    {{ get_payment_type_description('payment_type') }} as payment_type_description
from tripdata
where rn = 1

-- {% if var('is_test_run', default=true) %}
--   limit 100
-- {% endif %}