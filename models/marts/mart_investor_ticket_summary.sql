-- ============================================================================
-- Answers question 1: "Which investors raise the most support tickets and what
-- patterns exist in that behaviour?"
--
-- One row per investor (ALL investors, including those who never raised a
-- ticket, so the analyst can compare raisers vs non-raisers). Only tickets
-- whose requester resolved to that investor are counted — RM-raised tickets
-- are intentionally excluded here and analysed via the RM/partner views.
-- Grain: one row per investor.
-- ============================================================================
with investors as (
    select * from {{ ref('dim_investor') }}
),

investor_tickets as (
    select *
    from {{ ref('fct_tickets') }}
    where requester_type = 'investor'
      and investor_id is not null
),

agg as (
    select
        investor_id,
        count(*)                                              as ticket_count,
        count(*) filter (where is_resolved)                   as resolved_count,
        count(*) filter (where is_open)                       as open_count,
        count(*) filter (where priority = 'urgent')           as urgent_count,
        count(*) filter (where priority = 'high')             as high_count,
        avg(resolution_hours)                                 as avg_resolution_hours,
        median(resolution_hours)                              as median_resolution_hours,
        min(created_at)                                       as first_ticket_at,
        max(created_at)                                       as last_ticket_at
    from investor_tickets
    group by investor_id
)

select
    i.investor_id,
    i.full_name,
    i.email,
    i.country,
    i.entity_id,
    i.entity_name,
    i.entity_type,
    i.kyc_status,
    i.partner_id,
    i.partner_name,
    i.partner_type,
    i.is_rm_managed,

    coalesce(a.ticket_count, 0)   as ticket_count,
    coalesce(a.resolved_count, 0) as resolved_count,
    coalesce(a.open_count, 0)     as open_count,
    coalesce(a.urgent_count, 0)   as urgent_count,
    coalesce(a.high_count, 0)     as high_count,
    a.avg_resolution_hours,
    a.median_resolution_hours,
    a.first_ticket_at,
    a.last_ticket_at
from investors i
left join agg a on i.investor_id = a.investor_id
