-- ============================================================================
-- Requester resolution — the analytical heart of the model.
--
-- A Freshdesk ticket's requester can be one of FOUR types of person:
--   1. investor      — requester_email matches a platform_investors.email
--   2. rm            — requester_email matches a relationship_manager.email
--   3. internal      — requester_email is a @titanbay.com / @titanbay.co.uk
--                      address (IS team, ops staff, internal testing)
--   4. unknown       — email matches nothing (consumer/personal addresses, ex-
--                      users, or typos — 80 tickets in the current data)
--
-- Grain safety: emails are deduplicated to one row per address before joining,
-- so even if future data introduces duplicate investor registrations the ticket
-- grain can never fan out. A `_match_count` column surfaces any such collapse.
--
-- Partner attribution trust order:
--   investor email  →  RM email  →  label synonym lookup  →  null
-- `partner_attribution_method` records which rung was used.
--
-- Output grain: exactly one row per ticket.
-- ============================================================================
with tickets as (
    select * from {{ ref('stg_freshdesk__tickets') }}
),

investors as (
    select * from {{ ref('int_investors__enriched') }}
),

rms as (
    select * from {{ ref('int_relationship_managers__enriched') }}
),

-- Synonym seed: maps every observed partner_label variant → partner_id.
-- Uses keyword matching at seed-generation time; covers all 80 observed
-- label variants across 15 partners. Covers the IS team's inconsistent
-- free-text entry without any fuzzy-match runtime overhead.
label_synonyms as (
    select * from {{ ref('partner_label_synonyms') }}
),

-- One investor per email — deterministic: earliest registration, then id.
-- In the current data all 1 253 emails are unique, so this CTE collapses
-- nothing. It is here to protect the grain if duplicate registrations appear.
investor_by_email as (
    select
        email,
        investor_id,
        partner_id as investor_partner_id,
        count(*) over (partition by email) as investor_match_count
    from investors
    where email is not null
    qualify row_number() over (
        partition by email order by created_at asc, investor_id asc
    ) = 1
),

-- One RM per email, same treatment.
rm_by_email as (
    select
        rm_email,
        rm_id,
        partner_id as rm_partner_id,
        count(*) over (partition by rm_email) as rm_match_count
    from rms
    where rm_email is not null
    qualify row_number() over (
        partition by rm_email order by rm_id asc
    ) = 1
),

-- Normalised label lookup. The synonym seed stores one row per raw label
-- string, so UPPER/lower/mixed variants of the same label produce multiple
-- rows with the same label_norm after normalisation. We collapse to one row
-- per label_norm (all collisions map to the same partner_id, so this is safe
-- and deterministic) to prevent the join from fanning out the ticket grain.
label_lookup as (
    select
        lower(trim(label_raw)) as label_norm,
        partner_id as label_partner_id
    from label_synonyms
    qualify row_number() over (
        partition by lower(trim(label_raw)) order by label_raw
    ) = 1
),

resolved as (
    select
        t.ticket_id,
        t.requester_email,
        t.requester_name,
        t.subject,
        t.status,
        t.priority,
        t.created_at,
        t.resolved_at,
        t.tags_raw,
        t.partner_label,

        iv.investor_id,
        iv.investor_partner_id,
        iv.investor_match_count,
        rm.rm_id,
        rm.rm_partner_id,
        rm.rm_match_count,
        ll.label_partner_id,

        (iv.investor_id is not null) as matched_investor,
        (rm.rm_id is not null) as matched_rm,
        -- No overlap in current data, but flag defensively
        (iv.investor_id is not null and rm.rm_id is not null) as requester_matched_both,

        -- Internal Titanbay staff are their own class, not 'unknown'
        t.requester_email like '%@titanbay.com' as is_titanbay_com,
        t.requester_email like '%@titanbay.co.uk' as is_titanbay_co_uk,

        case
            when iv.investor_id is not null then 'investor'
            when rm.rm_id is not null then 'relationship_manager'
            when t.requester_email like '%@titanbay.%' then 'internal'
            else 'unknown'
        end as requester_type
    from tickets t
    left join investor_by_email iv on t.requester_email = iv.email
    left join rm_by_email rm on t.requester_email = rm.rm_email
    left join label_lookup ll on lower(trim(t.partner_label)) = ll.label_norm
)

select
    *,

    -- Authoritative partner, in trust order.
    -- Internal and unknown tickets can still be attributed via the label.
    coalesce(
        case when requester_type = 'investor' then investor_partner_id end,
        case when requester_type = 'relationship_manager' then rm_partner_id end,
        label_partner_id
    ) as partner_id,

    case
        when requester_type = 'investor' then 'investor_email_match'
        when requester_type = 'relationship_manager' then 'rm_email_match'
        when label_partner_id is not null then 'partner_label_fallback'
        else 'unresolved'
    end as partner_attribution_method
from resolved
