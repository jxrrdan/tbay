-- ============================================================================
-- Partner-level weekly pressure — per-partner cut of the team-wide pressure
-- series. Lets the IS team see which partners are driving load in a given week,
-- and plan partner-specific resourcing ahead of their close calendar.
--
-- Grain: one row per (partner, ISO week).
-- ============================================================================
with tickets as (
    select
        partner_id,
        created_week as week_start,
        count(*) as tickets_created,
        {{ count_if("priority in ('high', 'urgent')") }} as tickets_high_urgent,
        {{ count_if("requester_type = 'investor'") }} as investor_tickets,
        {{ count_if("requester_type = 'relationship_manager'") }} as rm_tickets
    from {{ ref('fct_tickets') }}
    where partner_id is not null
    group by partner_id, created_week
),

closes as (
    select
        partner_id,
        close_week as week_start,
        count(*) as closes_scheduled,
        {{ count_if("close_status = 'completed'") }} as closes_completed,
        {{ count_if("close_status = 'upcoming'") }} as closes_upcoming,
        sum(total_committed_aum_gbp) as committed_aum_gbp
    from {{ ref('dim_fund_close') }}
    group by partner_id, close_week
),

partners as (
    select * from {{ ref('dim_partner') }}
),

spine as (
    select
        partner_id,
        week_start
    from tickets
    union distinct
    select
        partner_id,
        week_start
    from closes
)

select
    s.partner_id,
    p.partner_name,
    p.partner_type,
    s.week_start,

    coalesce(t.tickets_created, 0) as tickets_created,
    coalesce(t.tickets_high_urgent, 0) as tickets_high_urgent,
    coalesce(t.investor_tickets, 0) as investor_tickets,
    coalesce(t.rm_tickets, 0) as rm_tickets,
    coalesce(c.closes_scheduled, 0) as closes_scheduled,
    coalesce(c.closes_completed, 0) as closes_completed,
    coalesce(c.closes_upcoming, 0) as closes_upcoming,
    coalesce(c.committed_aum_gbp, 0) as committed_aum_gbp
from spine s
left join tickets t on s.partner_id = t.partner_id and s.week_start = t.week_start
left join closes c on s.partner_id = c.partner_id and s.week_start = c.week_start
left join partners p on s.partner_id = p.partner_id
order by s.week_start asc, tickets_created desc
