-- ============================================================================
-- Board-level theme rollup — maps the 10 raw Freshdesk tags to 4 investment-
-- lifecycle themes and counts distinct tickets per theme per period.
--
-- The four themes and their constituent tags:
--   Identity & Compliance   — kyc, onboarding
--   Documents & Signatures  — documents, e-signature
--   Investment Process      — commitment, fund-info, payment
--   Platform & Access       — account, portal, access
--
-- Key design decision: a ticket may carry tags from multiple themes (e.g.
-- "documents, kyc"). We count it once per theme it touches — not once per
-- tag — so the theme totals reflect affected tickets, not raw tag frequency.
-- Summing across themes will overcount if tickets span multiple themes;
-- use ticket_count within a single theme row for comparisons.
--
-- Grain: one row per (theme, partner_id, week_start).
-- ============================================================================
with ticket_tags as (
    select * from {{ ref('fct_ticket_tags') }}
),

themes as (
    select * from {{ ref('tag_themes') }}
),

-- Join tags to themes, then deduplicate to one row per (ticket x theme)
-- so multi-tag tickets don't inflate theme counts.
ticket_themes as (
    select distinct
        tt.ticket_id,
        tt.partner_id,
        tt.requester_type,
        tt.created_at,
        th.theme,
        th.theme_label,
        th.theme_sort_order
    from ticket_tags tt
    inner join themes th on tt.tag = th.tag
),

-- Add calendar grain
with_calendar as (
    select
        theme,
        theme_label,
        theme_sort_order,
        partner_id,
        requester_type,
        {{ week_start('created_at') }}  as week_start,
        {{ month_start('created_at') }} as month_start,
        ticket_id
    from ticket_themes
)

select
    theme,
    theme_label,
    theme_sort_order,
    partner_id,
    week_start,
    month_start,
    requester_type,
    count(distinct ticket_id)   as ticket_count
from with_calendar
group by
    theme,
    theme_label,
    theme_sort_order,
    partner_id,
    week_start,
    month_start,
    requester_type
order by theme_sort_order, week_start
