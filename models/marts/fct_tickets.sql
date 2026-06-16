{{
    config(
        materialized='incremental',
        unique_key='ticket_id',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}
-- Ticket fact — one row per support ticket, with the requester resolved to a
-- person type and an authoritative partner. This is the spine an analyst joins
-- the dimensions onto. Grain: one row per ticket.
--
-- Incremental strategy: merge on ticket_id with a 3-day lookback window.
-- The lookback catches tickets whose status or resolved_at changed after
-- creation (e.g. open → resolved). For a full re-resolution after upstream
-- dimension changes (new investors / RMs), run with --full-refresh.
--
-- Note: staging and intermediate models are views, so the incremental filter
-- here is the only pushdown. For large volumes, materialise
-- int_tickets__requester_resolution as a table with its own incremental config.
with resolved as (
    select * from {{ ref('int_tickets__requester_resolution') }}
    {% if is_incremental() %}
    where cast(created_at as date) >= (
        select {{ date_sub_days('cast(max(created_at) as date)', 3) }}
        from {{ this }}
    )
    {% endif %}
)

select
    -- Keys
    ticket_id,
    investor_id,                    -- FK -> dim_investor (null unless investor)
    rm_id,                          -- FK -> dim_relationship_manager (null unless RM)
    partner_id,                     -- FK -> dim_partner (resolved, may be null)

    -- Requester classification
    requester_type,                 -- investor | relationship_manager | internal | unknown
    requester_email,
    requester_name,
    partner_attribution_method,
    requester_matched_both,
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
    cast(created_at as date)              as created_date,
    {{ week_start('created_at') }}        as created_week,
    {{ month_start('created_at') }}       as created_month,

    -- Measures
    (resolved_at is not null)             as is_resolved,
    (status in ('open', 'pending'))       as is_open,
    case
        when resolved_at is not null
        then {{ datediff_hours('created_at', 'resolved_at') }}
    end                                   as resolution_hours
from resolved
