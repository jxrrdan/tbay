---
type: table
title: mart_staffing_forecast
description: >
  Forward-looking ticket load estimate per upcoming fund close, based on each
  partner's historical average tickets per close.
resource: dbt://titanbay_is/marts/mart_staffing_forecast
tags: [mart, forecast, staffing, resourcing, close-calendar]
timestamp: 2026-06-17T00:00:00Z
grain: one row per upcoming close
materialization: table
layer: mart
---

# mart_staffing_forecast

Converts the known forward close calendar into a quantified ticket load
estimate. For each upcoming close, looks at how many tickets that partner
generated in the ±14-day window around their previous completed closes and
projects forward.

Use `no_historical_data` and `low_sample_warning` to flag estimates that
should be treated with less confidence.

The pressure window is configurable: `dbt build --vars 'close_pressure_window_days: 21'`.

# Schema

| Column | Description |
|---|---|
| `close_id` | Unique close identifier. Primary key. |
| `fund_name` | Name of the fund. |
| `partner_name` | Partner firm running the close. |
| `scheduled_close_date` | The close date. |
| `pressure_window_start` | Start of the attribution window (close date − 14 days). |
| `pressure_window_end` | End of the attribution window (close date + 14 days). |
| `historical_close_count` | Number of completed closes this forecast is based on. |
| `avg_tickets_per_close` | Mean tickets in the ±14-day window from historical closes. |
| `min_tickets_observed` | Minimum seen across historical closes. |
| `max_tickets_observed` | Maximum seen across historical closes. |
| `expected_tickets` | Point estimate (= avg, rounded). |
| `expected_high_urgent_tickets` | Estimated high/urgent subset. |
| `no_historical_data` | True = new partner with no completed closes. Use cross-partner average as a fallback. |
| `low_sample_warning` | True = fewer than 3 completed closes. Estimate is less reliable. |

# Examples

**Next 8 weeks of expected load:**
```sql
select scheduled_close_date, fund_name, partner_name,
       expected_tickets, min_tickets_observed, max_tickets_observed,
       no_historical_data, low_sample_warning
from mart_staffing_forecast
where pressure_window_end >= current_date
order by scheduled_close_date
```

**Total expected tickets by partner, next quarter:**
```sql
select partner_name,
       count(*) as closes_upcoming,
       sum(expected_tickets) as total_expected_tickets
from mart_staffing_forecast
where scheduled_close_date between current_date and current_date + interval '90' day
group by partner_name
order by total_expected_tickets desc
```

# Citations

- [mart_close_ticket_pressure](/knowledge/mart_close_ticket_pressure.md) — the historical actuals this forecast is built from
- [mart_is_pressure_weekly](/knowledge/mart_is_pressure_weekly.md) — team-wide weekly view
