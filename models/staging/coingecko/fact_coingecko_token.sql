with
    max_extraction as (
        select max(extraction_date) as max_date
        from {{ source("PROD_LANDING", "raw_coingecko_token_data") }}
    ),
    coin_data as (
        select
            regexp_substr(
                source_url,
                'https://pro-api.coingecko.com/api/v3/coins/([^/]*)',
                1,
                1,
                'e',
                1
            ) as coingecko_id,
            parse_json(source_json) as data
        from {{ source("PROD_LANDING", "raw_coingecko_token_data") }}
        where extraction_date = (select max_date from max_extraction)
    ),
    prices as (
        select
            coingecko_id,
            date(to_timestamp(value[0]::number / 1000)) as date,
            value[1]::float as prices,
            row_number() over (
                partition by coingecko_id, date(to_timestamp(value[0]::number / 1000))
                order by to_timestamp(value[0]::number / 1000)
            ) as rn
        from coin_data, lateral flatten(input => data:prices)
    ),
    market_caps as (
        select
            coingecko_id,
            date(to_timestamp(value[0]::number / 1000)) as date,
            value[1]::float as market_caps,
            row_number() over (
                partition by coingecko_id, date(to_timestamp(value[0]::number / 1000))
                order by to_timestamp(value[0]::number / 1000)
            ) as rn
        from coin_data, lateral flatten(input => data:market_caps)
    ),
    total_volumes as (
        select
            coingecko_id,
            date(to_timestamp(value[0]::number / 1000)) as date,
            value[1]::float as h24_volume_usd,
            row_number() over (
                partition by coingecko_id, date(to_timestamp(value[0]::number / 1000))
                order by to_timestamp(value[0]::number / 1000)
            ) as rn
        from coin_data, lateral flatten(input => data:total_volumes)
    )
-- Final select statement, joining only rows where rn=1 (i.e., the oldest value for
-- each date). Coingecko returns multiple prices/market caps/volumes for each date,
-- but we only want the oldest one, so we use the row_number() window function to
-- select only the oldest one.
select
    p.date,
    p.coingecko_id,
    p.prices as token_price_usd,
    m.market_caps as token_market_cap,
    t.h24_volume_usd as token_h24_volume_usd
from (select * from prices where rn = 1) p
join (select * from market_caps where rn = 1) m using (coingecko_id, date)
join (select * from total_volumes where rn = 1) t using (coingecko_id, date)
