-- Scheduled fund closes. A fund has multiple closes; each close draws down a
-- tranche of committed capital from a partner's investors. The scheduled date
-- is the signal we use to anticipate support pressure. Grain: one row per close.
with source as (
    select * from {{ ref('platform_fund_closes') }}
)

select
    close_id,
    fund_id,
    trim(fund_name) as fund_name,
    partner_id,
    cast(close_number as integer) as close_number,
    cast(scheduled_close_date as date) as scheduled_close_date,
    lower(trim(close_status)) as close_status,
    {{ cast_int64('total_committed_aum') }} as total_committed_aum_gbp
from source
