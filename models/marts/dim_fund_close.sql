-- Fund-close dimension with owning partner and a few derived calendar fields
-- that make the "anticipate pressure" analysis easier. Grain: one per close.
with closes as (
    select * from {{ ref('stg_platform__fund_closes') }}
),

partners as (
    select * from {{ ref('stg_platform__partners') }}
)

select
    closes.close_id,
    closes.fund_id,
    closes.fund_name,
    closes.close_number,
    closes.scheduled_close_date,
    closes.close_status,
    closes.total_committed_aum_gbp,

    closes.partner_id,
    partners.partner_name,
    partners.partner_type,

    -- Calendar helpers (Monday-anchored week to match the pressure mart)
    date_trunc('week',  closes.scheduled_close_date)  as close_week,
    date_trunc('month', closes.scheduled_close_date)  as close_month,
    (closes.close_status = 'upcoming')                as is_upcoming
from closes
left join partners on closes.partner_id = partners.partner_id
