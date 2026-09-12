{{ config(materialized='view') }}

-- Deduplicate on the emitted row, not on (vendorid, tpep_pickup_datetime).
--
-- That pair names a vendor-second, not a trip. About 2.7 distinct yellow trips
-- begin per vendor per second in NYC, so partitioning on it discarded 62.86% of
-- real trips: 274,556,460 guarded rows collapsed to 101,958,248 in the
-- 2015-2016 window. The previous `order by tpep_dropoff_datetime` then made the
-- survivor of each group the SHORTEST trip in it, which drove the yellow
-- distance p99 from 18.67 to 15.60 mi and the duration p99 from 58.32 to 38.42
-- min. Before that ordering existed the damage was invisible, because an
-- arbitrary winner is an unbiased sample of its group.
--
-- Measured 2026-09-06; see notes/2026-09-06-prep-cloud-baseline.md in the
-- pipeline repository.
--
-- Projecting first and then taking DISTINCT removes only true duplicates. It is
-- deterministic by construction, so it keeps what the earlier tiebreak was for,
-- without choosing a biased survivor.

with projected as (
  select
    -- identifiers. The surrogate key covers every emitted source column, so it
    -- is unique per distinct trip. The old two-column key was unique only
    -- because the broken dedup made it so; §5.3's out-of-fold encoder needs a
    -- row key that is genuinely unique.
    {{ dbt_utils.generate_surrogate_key([
        'vendorid', 'tpep_pickup_datetime', 'tpep_dropoff_datetime',
        'ratecodeid', 'pulocationid', 'dolocationid', 'store_and_fwd_flag',
        'passenger_count', 'trip_distance', 'fare_amount', 'extra', 'mta_tax',
        'tip_amount', 'tolls_amount', 'improvement_surcharge', 'total_amount',
        'payment_type']) }} as tripid,
    {{ dbt.safe_cast("vendorid", api.Column.translate_type("integer")) }} as vendorid,
    {{ dbt.safe_cast("ratecodeid", api.Column.translate_type("integer")) }} as ratecodeid,
    {{ dbt.safe_cast("pulocationid", api.Column.translate_type("integer")) }} as pickup_locationid,
    {{ dbt.safe_cast("dolocationid", api.Column.translate_type("integer")) }} as dropoff_locationid,

    -- timestamps
    cast(tpep_pickup_datetime as timestamp) as pickup_datetime,
    cast(tpep_pickup_datetime as date) as pickup_date,
    cast(tpep_dropoff_datetime as timestamp) as dropoff_datetime,

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
    {{ get_payment_type_description('payment_type') }} as payment_type_description

  from {{ source('staging','yellow_taxi_external_table') }}
  where vendorid is not null
    and cast(tpep_pickup_datetime as date) between '2015-01-01' and '2016-12-31'
)

select distinct * from projected
