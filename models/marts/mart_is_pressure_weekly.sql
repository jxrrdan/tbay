-- ============================================================================
-- Answers question 2 (resourcing): a team-wide weekly time series that places
-- ticket load next to fund-close activity, so the IS team can see how pressure
-- has historically tracked the close calendar and project forward from the
-- known schedule of upcoming closes.
--
-- Weeks are Monday-anchored. Grain: one row per ISO week.
-- ============================================================================
with tickets_created as (
    select
        created_week                                          as week_start,
        count(*)                                              as tickets_created,
        count(*) filter (where priority in ('high', 'urgent')) as tickets_high_urgent
    from {{ ref('fct_tickets') }}
    group by created_week
),

tickets_resolved as (
    select
        {{ week_start('resolved_at') }}                       as week_start,
        count(*)                                              as tickets_resolved
    from {{ ref('fct_tickets') }}
    where resolved_at is not null
    group by {{ week_start('resolved_at') }}
),

closes as (
    select
        close_week                                            as week_start,
        count(*)                                              as closes_scheduled,
        count(*) filter (where close_status = 'completed')    as closes_completed,
        count(*) filter (where close_status = 'upcoming')     as closes_upcoming,
        sum(total_committed_aum_gbp)                          as committed_aum_closing_gbp
    from {{ ref('dim_fund_close') }}
    group by close_week
),

week_spine as (
    select week_start from tickets_created
    union
    select week_start from tickets_resolved
    union
    select week_start from closes
)

select
    w.week_start,
    coalesce(tc.tickets_created, 0)        as tickets_created,
    coalesce(tc.tickets_high_urgent, 0)    as tickets_high_urgent,
    coalesce(tr.tickets_resolved, 0)       as tickets_resolved,
    coalesce(c.closes_scheduled, 0)        as closes_scheduled,
    coalesce(c.closes_completed, 0)        as closes_completed,
    coalesce(c.closes_upcoming, 0)         as closes_upcoming,
    coalesce(c.committed_aum_closing_gbp, 0) as committed_aum_closing_gbp
from week_spine w
left join tickets_created  tc on w.week_start = tc.week_start
left join tickets_resolved tr on w.week_start = tr.week_start
left join closes           c  on w.week_start = c.week_start
order by w.week_start
