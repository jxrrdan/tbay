-- ============================================================================
-- Attribution quality monitoring — tracks the rates of each partner
-- attribution method over time so data-health regressions are visible.
--
-- The two KPIs to watch:
--   unresolved_rate   — should approach 0 once platform IDs are stamped on
--                       tickets (see README reflection). Currently ~6.7%.
--   fallback_rate     — tickets relying on the manual partner_label fallback.
--                       High value = IS team not filling the label OR the
--                       synonym map needs updating.
--
-- Grain: one row per ISO week.
-- ============================================================================
with tickets as (
    select * from {{ ref('fct_tickets') }}
),

-- Stale upcoming closes: source-system data-entry gap where a close is still
-- marked 'upcoming' but its scheduled date has already passed. Count is a
-- constant across all weeks — it reflects current platform state, not history.
stale_closes as (
    select count(*) as stale_upcoming_close_count
    from {{ ref('dim_fund_close') }}
    where is_stale_upcoming
),

weekly as (
    select
        created_week as week_start,
        count(*) as total_tickets,

        -- Requester type breakdown
        {{ count_if("requester_type = 'investor'") }} as investor_tickets,
        {{ count_if("requester_type = 'relationship_manager'") }} as rm_tickets,
        {{ count_if("requester_type = 'internal'") }} as internal_tickets,
        {{ count_if("requester_type = 'unknown'") }} as unknown_tickets,

        -- Partner attribution method breakdown
        {{ count_if("partner_attribution_method = 'investor_email_match'") }} as attr_investor_email,
        {{ count_if("partner_attribution_method = 'rm_email_match'") }} as attr_rm_email,
        {{ count_if("partner_attribution_method = 'partner_label_fallback'") }} as attr_label_fallback,
        {{ count_if("partner_attribution_method = 'unresolved'") }} as attr_unresolved,

        -- Ambiguity flags
        {{ count_if('investor_email_is_ambiguous') }} as ambiguous_investor_email_count,
        {{ count_if('rm_email_is_ambiguous') }} as ambiguous_rm_email_count
    from tickets
    group by created_week
)

select
    w.week_start,
    w.total_tickets,

    w.investor_tickets,
    w.rm_tickets,
    w.internal_tickets,
    w.unknown_tickets,

    w.attr_investor_email,
    w.attr_rm_email,
    w.attr_label_fallback,
    w.attr_unresolved,

    w.ambiguous_investor_email_count,
    w.ambiguous_rm_email_count,

    -- Rates (the KPIs to monitor)
    round(w.attr_unresolved * 100.0 / nullif(w.total_tickets, 0), 2) as unresolved_rate_pct,
    round(w.attr_label_fallback * 100.0 / nullif(w.total_tickets, 0), 2) as fallback_rate_pct,
    round(w.unknown_tickets * 100.0 / nullif(w.total_tickets, 0), 2) as unknown_requester_rate_pct,
    round(w.internal_tickets * 100.0 / nullif(w.total_tickets, 0), 2) as internal_requester_rate_pct,

    -- Close calendar data quality: closes still marked 'upcoming' with a past
    -- scheduled date. Should be 0. Non-zero means the source system has gaps
    -- that corrupt mart_staffing_forecast if not filtered out.
    s.stale_upcoming_close_count
from weekly w
cross join stale_closes s
order by w.week_start
