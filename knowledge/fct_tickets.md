---
type: table
title: fct_tickets
description: >
  One row per Freshdesk support ticket with requester resolved to a person type
  and an authoritative partner. The spine for all ticket analysis — join every
  other table to this.
resource: dbt://titanbay_is/marts/fct_tickets
tags: [fact, tickets, spine, incremental]
timestamp: 2026-06-17T00:00:00Z
grain: one row per ticket
materialization: incremental (merge on ticket_id, 3-day lookback)
layer: mart
---

# fct_tickets

The central fact table. Every mart joins back to this.

The core challenge this table solves: a Freshdesk ticket has no `investor_id`
or `partner_id` — only a requester email. This table resolves that email to
a [requester type](/knowledge/concepts/requester_types.md) and derives an
authoritative [partner](/knowledge/concepts/partner_attribution.md).

# Schema

| Column | Type | Description |
|---|---|---|
| `ticket_id` | integer | Freshdesk ticket number. Primary key. |
| `requester_email` | string | Normalised (lower/trim) email of the requester. |
| `requester_type` | string | `investor` / `relationship_manager` / `internal` / `unknown`. See [requester types](/knowledge/concepts/requester_types.md). |
| `investor_id` | string | FK → dim_investor. Null unless requester is an investor. |
| `rm_id` | string | FK → dim_relationship_manager. Null unless requester is an RM. |
| `partner_id` | string | FK → dim_partner. Derived — see [partner attribution](/knowledge/concepts/partner_attribution.md). |
| `partner_attribution_method` | string | How partner_id was derived: `investor_email_match` → `rm_email_match` → `partner_label_fallback` → `unresolved`. |
| `status` | string | `open` / `pending` / `resolved` / `closed`. |
| `priority` | string | `low` / `medium` / `high` / `urgent`. |
| `created_at` | timestamp | When the ticket was opened. |
| `resolved_at` | timestamp | When the ticket was resolved. Null if still open. |
| `created_week` | date | Monday of the ISO week the ticket was created. |
| `created_month` | date | First of the month the ticket was created. |
| `is_resolved` | boolean | True when status is `resolved` or `closed`. Use this instead of filtering on status values. |
| `is_open` | boolean | True for `open` and `pending`. |
| `resolution_hours` | float | Hours from creation to resolution. Null if unresolved. |
| `investor_email_is_ambiguous` | boolean | True if multiple investors share this email (rare; one was selected deterministically). |
| `partner_label` | string | Raw IS-entered label. Do not use for analysis — use `partner_id`. |

## Things not to do

- Do not filter `WHERE requester_type = 'investor'` to get "all investor tickets" and then count by `partner_id` — RM-raised tickets belong to partners too.
- Do not trust `partner_label` for aggregation; it has 80 inconsistent variants for 15 partners.

# Examples

**All open high-priority tickets this week:**
```sql
select ticket_id, requester_email, requester_type, partner_id, priority, created_at
from fct_tickets
where is_open = true
  and priority in ('high', 'urgent')
  and created_week = date_trunc('week', current_date)
order by created_at
```

**Partner ticket volume last 90 days:**
```sql
select p.partner_name, count(*) as tickets
from fct_tickets t
join dim_partner p using (partner_id)
where t.created_at >= current_date - interval '90' day
group by p.partner_name
order by tickets desc
```

# Citations

- [mart_investor_ticket_summary](/knowledge/mart_investor_ticket_summary.md) — aggregated per investor, built from this table
- [mart_is_pressure_weekly](/knowledge/mart_is_pressure_weekly.md) — weekly aggregation from this table
- [Entity resolution concept](/knowledge/concepts/entity_resolution.md) — explains how requester_type is derived
