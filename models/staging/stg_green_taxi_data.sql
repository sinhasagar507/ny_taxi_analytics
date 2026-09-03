{{ 
  config(
    materialized='view'
  ) 
}}

with tripdata as (
  select *,
    -- The tie-break MUST be deterministic. See the same comment in
    -- stg_yellow_taxi_data.sql: an unordered row_number() makes fact_trips return a
    -- different row count on every build. Ordering by every remaining column leaves ties
    -- only between rows that are identical.
    row_number() over(
      partition by vendorid, lpep_pickup_datetime
      order by lpep_dropoff_datetime, pulocationid, dolocationid, payment_type,
               ratecodeid, store_and_fwd_flag, passenger_count, trip_distance,
               fare_amount, extra, mta_tax, tip_amount, tolls_amount, ehail_fee,
               improvement_surcharge, total_amount
      -- trip_type and congestion_surcharge excluded: the external table declares both
      -- INT64 but the source Parquet stores DOUBLE for the 2015-2016 green files, so
      -- ordering by either throws a type error. Neither is selected by this model (see
      -- the commented-out trip_type_mode block below), so omitting them from the
      -- tiebreak does not affect the emitted columns' determinism.
    ) as rn
  from {{ source('staging','green_taxi_external_table') }}
  where vendorid is not null 
    and cast(lpep_pickup_datetime as date) between '2015-01-01' and '2016-12-31'
)

-- Get the mode of trip_type, aliasing the column to avoid ambiguity
-- trip_type_mode as (
--   select trip_type as mode_trip_type
--   from (
--     select trip_type, count(*) as freq
--     from tripdata
--     where trip_type is not null
--     group by trip_type
--     order by freq desc
--     limit 1
--   ) as mode_table
-- )

select
    -- identifiers
    {{ dbt_utils.generate_surrogate_key(['vendorid', 'lpep_pickup_datetime']) }} as tripid,
    {{ dbt.safe_cast("vendorid", api.Column.translate_type("integer")) }} as vendorid,
    {{ dbt.safe_cast("ratecodeid", api.Column.translate_type("integer")) }} as ratecodeid,
    {{ dbt.safe_cast("pulocationid", api.Column.translate_type("integer")) }} as pickup_locationid,
    {{ dbt.safe_cast("dolocationid", api.Column.translate_type("integer")) }} as dropoff_locationid,
    
    -- timestamps
    cast(lpep_pickup_datetime as timestamp) as pickup_datetime,
    cast(lpep_pickup_datetime as date) as pickup_date,  -- New column extracted as date
    cast(lpep_dropoff_datetime as timestamp) as dropoff_datetime,
    
    -- trip info
    store_and_fwd_flag,
    {{ dbt.safe_cast("passenger_count", api.Column.translate_type("integer")) }} as passenger_count,
    cast(trip_distance as numeric) as trip_distance,
    -- coalesce(
    --     {{ dbt.safe_cast("tripdata.trip_type", api.Column.translate_type("integer")) }},
    --     trip_type_mode.mode_trip_type
    -- ) as trip_type,
    -- {{ dbt.safe_cast("trip_type", api.Column.translate_type("numeric")) }} as trip_type,

    -- payment info
    cast(fare_amount as numeric) as fare_amount,
    cast(extra as numeric) as extra,
    cast(mta_tax as numeric) as mta_tax,
    cast(tip_amount as numeric) as tip_amount,
    cast(tolls_amount as numeric) as tolls_amount,
    cast(improvement_surcharge as numeric) as improvement_surcharge,
    cast(total_amount as numeric) as total_amount,
    coalesce({{ dbt.safe_cast("payment_type", api.Column.translate_type("integer")) }},0) as payment_type,
    {{ get_payment_type_description("payment_type") }} as payment_type_description

from tripdata
-- cross join trip_type_mode
where rn = 1

-- {% if var('is_test_run', default=true) %}
--   limit 100
-- {% endif %}
