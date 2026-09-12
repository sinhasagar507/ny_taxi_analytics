{{ config(materialized='view') }}

-- Same defect and same fix as stg_yellow_taxi_data.sql: see the comment there.
-- The old dedup partitioned on (vendorid, lpep_pickup_datetime), which names a
-- vendor-second rather than a trip, and its ordering selected the shortest trip
-- in each group.
--
-- Projecting first also removes the type problem the old comment recorded:
-- trip_type and congestion_surcharge could not appear in an `order by`, because
-- the external table declares INT64 while the 2015-2016 green parquet stores
-- DOUBLE. Neither column is emitted, so neither reaches the DISTINCT.

with projected as (
  select
    -- identifiers. Covers every emitted source column, so it is unique per
    -- distinct trip.
    {{ dbt_utils.generate_surrogate_key([
        'vendorid', 'lpep_pickup_datetime', 'lpep_dropoff_datetime',
        'ratecodeid', 'pulocationid', 'dolocationid', 'store_and_fwd_flag',
        'passenger_count', 'trip_distance', 'fare_amount', 'extra', 'mta_tax',
        'tip_amount', 'tolls_amount', 'improvement_surcharge', 'total_amount',
        'payment_type']) }} as tripid,
    {{ dbt.safe_cast("vendorid", api.Column.translate_type("integer")) }} as vendorid,
    {{ dbt.safe_cast("ratecodeid", api.Column.translate_type("integer")) }} as ratecodeid,
    {{ dbt.safe_cast("pulocationid", api.Column.translate_type("integer")) }} as pickup_locationid,
    {{ dbt.safe_cast("dolocationid", api.Column.translate_type("integer")) }} as dropoff_locationid,

    -- timestamps
    cast(lpep_pickup_datetime as timestamp) as pickup_datetime,
    cast(lpep_pickup_datetime as date) as pickup_date,
    cast(lpep_dropoff_datetime as timestamp) as dropoff_datetime,

    -- trip info
    store_and_fwd_flag,
    {{ dbt.safe_cast("passenger_count", api.Column.translate_type("integer")) }} as passenger_count,
    cast(trip_distance as numeric) as trip_distance,

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

  from {{ source('staging','green_taxi_external_table') }}
  where vendorid is not null
    and cast(lpep_pickup_datetime as date) between '2015-01-01' and '2016-12-31'
)

select distinct * from projected
