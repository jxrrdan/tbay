---
type: table
title: mart_is_pressure_weekly
description: >
  Team-wide weekly ticket load alongside fund close activity. Use this to see
  how volume tracks the close calendar historically and to plan ahead.
resource: dbt://titanbay_is/marts/mart_is_pressure_weekly
tags: [mart, weekly, pressure, resourcing, close-calendar]
timestamp: 2026-06-17T00:00:00Z
grain: one row per ISO week (Monday-anchored)
materialization: table
layer: mart
---

# mart_is_pressure_weekly

Answers question 2: when is the IS team likely to be under pressure?

Puts ticket volume and the fund close calendar on the same weekly time series
so the relationship between closes and support load is visible at a glance.
Plot `tickets_created` against `closes_scheduled` to see the historical
lead/lag pattern, then use the known forward close calendar to anticipate
future pressure.

For a per-partner breakdown of the same series, use
[mart_partner_pressure_weekly](/knowledge/mart_partner_pressure_weekly.md).

# Schema

| Column | Description |
|---|---|
| `week_start` | Monday of the ISO week (DATE). Primary key. |
| `tickets_created` | New tickets opened that week. |
| `tickets_high_urgent` | Subset of tickets_created at high or urgent priority. |
| `tickets_resolved` | Tickets resolved that week (may include tickets from prior weeks). |
| `closes_scheduled` | Fund closes with scheduled_close_date in this week. |
| `closes_upcoming` | Of those, closes still in upcoming status. |
| `committed_aum_closing_gbp` | Total AUM committed across closes in this week. |

# Examples

**Historical view — ticket volume vs closes, last 6 months:**
```sql
select week_start, tickets_created, tickets_high_urgent,
       closes_scheduled, committed_aum_closing_gbp
from mart_is_pressure_weekly
where week_start >= current_date - interval '180' day
order by week_start
```

**Weeks with the highest pressure historically:**
```sql
select week_start, tickets_created, tickets_high_urgent, closes_scheduled
from mart_is_pressure_weekly
order by tickets_high_urgent desc
limit 10
```

# Citations

- [mart_partner_pressure_weekly](/knowledge/mart_partner_pressure_weekly.md) — same series split by partner
- [mart_staffing_forecast](/knowledge/mart_staffing_forecast.md) — forward-looking load estimate per upcoming close
- [mart_close_ticket_pressure](/knowledge/mart_close_ticket_pressure.md) — per-close ticket attribution
