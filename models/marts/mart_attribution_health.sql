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

weekly as (
    select
        created_week                                                         as week_start,
        count(*)                                                             as total_tickets,

        -- Requester type breakdown
        count(*) filter (where requester_type = 'investor')                 as investor_tickets,
        count(*) filter (where requester_type = 'relationship_manager')     as rm_tickets,
        count(*) filter (where requester_type = 'internal')                 as internal_tickets,
        count(*) filter (where requester_type = 'unknown')                  as unknown_tickets,

        -- Partner attribution method breakdown
        count(*) filter (where partner_attribution_method = 'investor_email_match')   as attr_investor_email,
        count(*) filter (where partner_attribution_method = 'rm_email_match')         as attr_rm_email,
        count(*) filter (where partner_attribution_method = 'partner_label_fallback') as attr_label_fallback,
        count(*) filter (where partner_attribution_method = 'unresolved')             as attr_unresolved,

        -- Ambiguity flags
        count(*) filter (where investor_email_is_ambiguous)                 as ambiguous_investor_email_count,
        count(*) filter (where rm_email_is_ambiguous)                       as ambiguous_rm_email_count
    from tickets
    group by created_week
)

select
    week_start,
    total_tickets,

    investor_tickets,
    rm_tickets,
    internal_tickets,
    unknown_tickets,

    attr_investor_email,
    attr_rm_email,
    attr_label_fallback,
    attr_unresolved,

    ambiguous_investor_email_count,
    ambiguous_rm_email_count,

    -- Rates (the KPIs to monitor)
    round(attr_unresolved    * 100.0 / nullif(total_tickets, 0), 2) as unresolved_rate_pct,
    round(attr_label_fallback * 100.0 / nullif(total_tickets, 0), 2) as fallback_rate_pct,
    round(unknown_tickets     * 100.0 / nullif(total_tickets, 0), 2) as unknown_requester_rate_pct,
    round(internal_tickets    * 100.0 / nullif(total_tickets, 0), 2) as internal_requester_rate_pct
from weekly
order by week_start
