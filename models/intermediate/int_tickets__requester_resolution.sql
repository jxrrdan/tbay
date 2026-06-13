-- ============================================================================
-- Requester resolution — the analytical heart of the model.
--
-- A Freshdesk ticket's requester can be one of THREE types of person:
--   1. an investor      (requester_email matches a platform_investors.email)
--   2. an RM            (requester_email matches a relationship_manager.email)
--   3. unknown          (email matches neither — e.g. an ex-user, a typo, or
--                        an internal/forwarded address)
--
-- Two grain hazards are handled explicitly here:
--   * One email may map to MORE THAN ONE investor (duplicate registrations).
--     We collapse to a single investor per email with a deterministic rule
--     (earliest-registered wins) and keep a *_match_count so the ambiguity is
--     visible rather than silently fanning out the ticket grain.
--   * An email may match BOTH an investor and an RM. We apply investor-first
--     precedence and flag `requester_matched_both` for audit. (Investor-first
--     keeps the "which investors raise the most tickets" question answerable;
--     the flag lets an analyst trivially flip the rule.)
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

partners as (
    select * from {{ ref('stg_platform__partners') }}
),

-- One investor per email. Deterministic: earliest registration, then id.
investor_by_email as (
    select
        email,
        investor_id,
        partner_id              as investor_partner_id,
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
        partner_id              as rm_partner_id,
        count(*) over (partition by rm_email) as rm_match_count
    from rms
    where rm_email is not null
    qualify row_number() over (
        partition by rm_email order by rm_id asc
    ) = 1
),

-- Last-resort partner attribution from the manual free-text label, matched on
-- an exact normalised partner name. Deliberately conservative: the label is
-- unreliable (~44% null, inconsistent), so we only trust an exact name hit and
-- never let it override an email-based match.
partner_by_label as (
    select
        lower(trim(partner_name)) as partner_label_norm,
        partner_id                as label_partner_id
    from partners
    qualify row_number() over (
        partition by lower(trim(partner_name)) order by partner_id
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
        pl.label_partner_id,

        (iv.investor_id is not null)                       as matched_investor,
        (rm.rm_id is not null)                             as matched_rm,
        (iv.investor_id is not null and rm.rm_id is not null) as requester_matched_both,

        case
            when iv.investor_id is not null then 'investor'
            when rm.rm_id is not null       then 'relationship_manager'
            else 'unknown'
        end as requester_type
    from tickets t
    left join investor_by_email iv on t.requester_email = iv.email
    left join rm_by_email       rm on t.requester_email = rm.rm_email
    left join partner_by_label  pl on lower(trim(t.partner_label)) = pl.partner_label_norm
)

select
    *,

    -- Authoritative partner for the ticket, in trust order:
    --   investor email  ->  RM email  ->  exact partner-label name match.
    coalesce(
        case when requester_type = 'investor'             then investor_partner_id end,
        case when requester_type = 'relationship_manager' then rm_partner_id        end,
        label_partner_id
    ) as partner_id,

    case
        when requester_type = 'investor'             then 'investor_email_match'
        when requester_type = 'relationship_manager' then 'rm_email_match'
        when label_partner_id is not null            then 'partner_label_fallback'
        else 'unresolved'
    end as partner_attribution_method
from resolved
