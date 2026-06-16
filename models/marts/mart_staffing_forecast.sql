-- ============================================================================
-- Forward staffing forecast — translates the upcoming close calendar into
-- an expected ticket load estimate using historical averages per partner.
--
-- Method:
--   1. Compute avg tickets-per-close (and hi/urgent subset) from completed
--      closes for each partner, using the same ±window used in
--      mart_close_ticket_pressure.
--   2. Join to upcoming closes and project expected load.
--   3. Flag closes from partners with no completed-close history so analysts
--      know where the estimate is missing.
--
-- Interpretation:
--   expected_tickets is a point estimate. The min/max observed columns give
--   the range from historical closes, letting the IS team apply a cushion.
--   For a probabilistic forecast, this model is the input layer — regression
--   or simulation belongs in a BI tool on top of this output.
--
-- Grain: one row per upcoming close. The pressure window columns
-- (window_start, window_end) tell the analyst which date range to staff for.
-- ============================================================================
{% set window_days = var('close_pressure_window_days', 14) %}

with close_pressure as (
    -- Historical per-close ticket counts from the existing mart
    select * from {{ ref('mart_close_ticket_pressure') }}
),

historical_by_partner as (
    select
        partner_id,
        count(*)                            as completed_close_count,
        avg(tickets_in_window)              as avg_tickets_per_close,
        min(tickets_in_window)              as min_tickets_observed,
        max(tickets_in_window)              as max_tickets_observed,
        avg(tickets_high_urgent)            as avg_high_urgent_per_close
    from close_pressure
    where close_status = 'completed'
    group by partner_id
),

upcoming as (
    select * from {{ ref('dim_fund_close') }}
    where close_status = 'upcoming'
)

select
    u.close_id,
    u.fund_id,
    u.fund_name,
    u.close_number,
    u.partner_id,
    u.partner_name,
    u.partner_type,
    u.scheduled_close_date,
    u.total_committed_aum_gbp,

    -- Pressure window this close will generate load across
    {{ date_sub_days('u.scheduled_close_date', window_days) }} as pressure_window_start,
    {{ date_add_days('u.scheduled_close_date', window_days) }} as pressure_window_end,

    -- Historical basis
    h.completed_close_count             as historical_close_count,
    round(h.avg_tickets_per_close, 1)   as avg_tickets_per_close,
    h.min_tickets_observed,
    h.max_tickets_observed,
    round(h.avg_high_urgent_per_close, 1) as avg_high_urgent_per_close,

    -- Forecast (rounded to whole tickets)
    round(h.avg_tickets_per_close, 0)      as expected_tickets,
    round(h.avg_high_urgent_per_close, 0)  as expected_high_urgent_tickets,

    -- Confidence flags
    (h.partner_id is null)              as no_historical_data,
    (h.completed_close_count < 3)       as low_sample_warning
from upcoming u
left join historical_by_partner h on u.partner_id = h.partner_id
order by u.scheduled_close_date
