{{ config(
    materialized='view'
) }}

with climate_data as (
    select *
    from {{ source('staging', 'climate_external_table') }}
)

select
    -- Primary key based on MJD-derived date
    date_add(date('1858-11-17'), interval cast(mjd as int64) day) as climate_date,

    -- Other selected fields
    {{ dbt.safe_cast("mjd", api.Column.translate_type("integer")) }} as mjd,

    cast(cloudCover      as numeric) as cloudCover,
    cast(humidity        as numeric) as humidity,
    cast(dewPoint        as numeric) as dewPoint,
    cast(precipIntensity as numeric) as precipIntensity,
    cast(temperatureHigh as numeric) as highTemp,
    cast(temperatureLow  as numeric) as lowTemp,
    cast(visibility      as numeric) as visibility,
    cast(windSpeed       as numeric) as windSpeed

from climate_data

where
  date_add(date('1858-11-17'), interval cast(mjd as int64) day)
    between date('2015-01-01') and date('2015-12-31')
