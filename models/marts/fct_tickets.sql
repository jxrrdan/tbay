-- Ticket fact — one row per support ticket, with the requester resolved to a
-- person type and an authoritative partner. This is the spine an analyst joins
-- the dimensions onto. Grain: one row per ticket.
with resolved as (
    select * from {{ ref('int_tickets__requester_resolution') }}
)

select
    -- Keys
    ticket_id,
    investor_id,                    -- FK -> dim_investor (null unless investor)
    rm_id,                          -- FK -> dim_relationship_manager (null unless RM)
    partner_id,                     -- FK -> dim_partner (resolved, may be null)

    -- Requester classification
    requester_type,                 -- investor | relationship_manager | unknown
    requester_email,
    requester_name,
    partner_attribution_method,
    requester_matched_both,
    -- Surfaces duplicate-email ambiguity that was collapsed upstream
    (coalesce(investor_match_count, 0) > 1) as investor_email_is_ambiguous,
    (coalesce(rm_match_count, 0) > 1)       as rm_email_is_ambiguous,

    -- Descriptive ticket attributes
    subject,
    status,
    priority,
    partner_label,                  -- raw manual label, kept for audit only

    -- Timing
    created_at,
    resolved_at,
    cast(created_at as date)                   as created_date,
    date_trunc('week',  created_at)            as created_week,
    date_trunc('month', created_at)            as created_month,

    -- Measures
    (resolved_at is not null)                  as is_resolved,
    (status in ('open', 'pending'))            as is_open,
    case
        when resolved_at is not null
        then (epoch(resolved_at) - epoch(created_at)) / 3600.0
    end                                         as resolution_hours
from resolved
