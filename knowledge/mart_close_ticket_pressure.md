---
type: table
title: mart_close_ticket_pressure
description: >
  One row per fund close (completed and upcoming) showing how many tickets
  were generated within the ±14-day window around the close date.
resource: dbt://titanbay_is/marts/mart_close_ticket_pressure
tags: [mart, close, pressure, tickets]
timestamp: 2026-06-17T00:00:00Z
grain: one row per fund close
materialization: table
layer: mart
---

# mart_close_ticket_pressure

Shows how many tickets each close actually generated. Used as the historical
training data for [mart_staffing_forecast](/knowledge/mart_staffing_forecast.md).

**Important:** tickets near overlapping closes from the same partner are
attributed to both closes. Do not sum `tickets_in_window` across closes and
expect it to equal total partner tickets — it will overcount.

# Schema

| Column | Description |
|---|---|
| `close_id` | Unique close identifier. Primary key. |
| `fund_name` | Name of the fund. |
| `partner_name` | Partner firm. |
| `close_status` | `completed` / `upcoming` / `cancelled`. |
| `scheduled_close_date` | The close date. |
| `pressure_window_start` | Close date − 14 days. |
| `pressure_window_end` | Close date + 14 days. |
| `tickets_in_window` | Tickets from this partner in the ±14-day window. |
| `tickets_before_close` | Subset created before the close date. |
| `tickets_on_or_after_close` | Subset created on or after the close date. |
| `tickets_high_urgent` | High/urgent subset within the window. |

# Examples

**Highest-pressure completed closes:**
```sql
select fund_name, partner_name, scheduled_close_date,
       tickets_in_window, tickets_high_urgent
from mart_close_ticket_pressure
where close_status = 'completed'
order by tickets_in_window desc
limit 20
```

# Citations

- [mart_staffing_forecast](/knowledge/mart_staffing_forecast.md) — forward estimates built from these actuals
- [mart_is_pressure_weekly](/knowledge/mart_is_pressure_weekly.md) — weekly team view
