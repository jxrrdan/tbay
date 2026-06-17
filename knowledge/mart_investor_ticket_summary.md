---
type: table
title: mart_investor_ticket_summary
description: >
  Per-investor ticket behaviour summary. One row per investor, including investors
  with zero tickets. Use this for "who raises the most" questions.
resource: dbt://titanbay_is/marts/mart_investor_ticket_summary
tags: [mart, investor, summary, behaviour]
timestamp: 2026-06-17T00:00:00Z
grain: one row per investor
materialization: table
layer: mart
---

# mart_investor_ticket_summary

Answers question 1: which investors raise the most support tickets, and what
patterns exist in that behaviour?

Includes every investor — even those with zero tickets — so you can segment
active vs inactive support users. Only counts tickets raised directly by the
investor; RM-raised tickets are excluded to avoid inflating individual counts.

# Schema

| Column | Description |
|---|---|
| `investor_id` | Unique investor identifier. Primary key. |
| `full_name` | Investor display name. |
| `email` | Registered platform email. |
| `partner_name` | The partner firm this investor belongs to. |
| `partner_type` | `wealth_manager` / `fund_manager` / `family_office`. |
| `entity_name` | The investing entity name. |
| `entity_type` | `individual` / `corporate` / `trust` / `pension_fund`. |
| `kyc_status` | `approved` / `pending` / `expired` / `rejected`. |
| `is_rm_managed` | True if this investor has a relationship manager. |
| `ticket_count` | Total tickets raised directly by this investor. |
| `resolved_count` | Tickets resolved. |
| `open_count` | Tickets currently open or pending. |
| `urgent_count` | Tickets at urgent priority. |
| `high_count` | Tickets at high priority. |
| `avg_resolution_hours` | Mean hours to resolution for this investor's tickets. |
| `median_resolution_hours` | Median hours to resolution. |
| `first_ticket_at` | Timestamp of their first ever ticket. |
| `last_ticket_at` | Timestamp of their most recent ticket. |

# Examples

**Top 10 investors by open ticket backlog:**
```sql
select full_name, partner_name, ticket_count, open_count, urgent_count
from mart_investor_ticket_summary
where ticket_count > 0
order by open_count desc, ticket_count desc
limit 10
```

**Investors with slow resolution times (median > 1 week):**
```sql
select full_name, partner_name, ticket_count,
       round(median_resolution_hours / 24, 1) as median_days
from mart_investor_ticket_summary
where median_resolution_hours > 168
order by median_resolution_hours desc
```

**Zero-ticket investors by partner (platform adoption view):**
```sql
select partner_name, count(*) as investors_never_raised_ticket
from mart_investor_ticket_summary
where ticket_count = 0
group by partner_name
order by investors_never_raised_ticket desc
```

# Citations

- [fct_tickets](/knowledge/fct_tickets.md) — underlying fact table
- [Requester types](/knowledge/concepts/requester_types.md) — why RM-raised tickets are excluded here
