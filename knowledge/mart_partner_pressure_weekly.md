---
type: table
title: mart_partner_pressure_weekly
description: >
  Per-partner weekly ticket load alongside fund close activity. Same series as
  mart_is_pressure_weekly but split by partner firm.
resource: dbt://titanbay_is/marts/mart_partner_pressure_weekly
tags: [mart, partner, weekly, pressure]
timestamp: 2026-06-17T00:00:00Z
grain: one row per (partner, ISO week). Weeks with no tickets and no closes for a partner are excluded.
materialization: table
layer: mart
---

# mart_partner_pressure_weekly

Use this to see which partner firm is driving ticket load in any given week.
Weeks with no tickets and no closes for a given partner are excluded from
the output.

For the team-wide total (all partners combined), use
[mart_is_pressure_weekly](/knowledge/mart_is_pressure_weekly.md).

# Schema

| Column | Description |
|---|---|
| `partner_id` | FK → dim_partner. |
| `partner_name` | Partner firm name. |
| `week_start` | Monday of the ISO week. Composite key with partner_id. |
| `tickets_created` | New tickets from this partner that week. |
| `tickets_high_urgent` | High/urgent subset. |
| `tickets_resolved` | Resolved that week (may include older tickets). |
| `closes_scheduled` | Closes for this partner in this week. |
| `committed_aum_closing_gbp` | AUM from this partner's closes in this week. |

# Examples

**Which partner has driven the most tickets in the last 4 weeks:**
```sql
select partner_name, sum(tickets_created) as tickets
from mart_partner_pressure_weekly
where week_start >= current_date - interval '28' day
group by partner_name
order by tickets desc
```

# Citations

- [mart_is_pressure_weekly](/knowledge/mart_is_pressure_weekly.md) — team-wide version of this mart
- [fct_tickets](/knowledge/fct_tickets.md) — underlying fact table
