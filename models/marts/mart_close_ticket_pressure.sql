-- ============================================================================
-- Answers question 2 (forecasting): how much support load does each fund close
-- generate? For every close we count the partner's tickets in a window around
-- the scheduled close date (default +/- 14 days, see var `close_pressure_window_days`).
--
-- This turns the close calendar into a planning tool: average tickets-per-close
-- from completed closes x the count of upcoming closes ~ expected future load.
--
-- Grain: one row per close. NOTE: windows around closes of the same partner can
-- overlap, so a single ticket may be counted against more than one close. This
-- is load *attribution*, not a partition — do not sum tickets_in_window across
-- closes and expect it to equal total tickets.
-- ============================================================================
{% set window_days = var('close_pressure_window_days', 14) %}

with closes as (
    select * from {{ ref('dim_fund_close') }}
),

partner_tickets as (
    select
        ticket_id,
        partner_id,
        created_date,
        priority
    from {{ ref('fct_tickets') }}
    where partner_id is not null
)

select
    c.close_id,
    c.fund_id,
    c.fund_name,
    c.close_number,
    c.partner_id,
    c.partner_name,
    c.scheduled_close_date,
    c.close_status,
    c.total_committed_aum_gbp,

    count(t.ticket_id) as tickets_in_window,
    {{ count_if('t.created_date < c.scheduled_close_date') }} as tickets_before_close,
    {{ count_if('t.created_date >= c.scheduled_close_date') }} as tickets_on_or_after_close,
    {{ count_if("t.priority in ('high', 'urgent')") }} as tickets_high_urgent
from closes c
left join partner_tickets t
    on
        c.partner_id = t.partner_id
        and t.created_date between {{ date_sub_days('c.scheduled_close_date', window_days) }}
        and {{ date_add_days('c.scheduled_close_date', window_days) }}
group by
    c.close_id, c.fund_id, c.fund_name, c.close_number, c.partner_id,
    c.partner_name, c.scheduled_close_date, c.close_status, c.total_committed_aum_gbp
