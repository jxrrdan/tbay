---
type: table
title: mart_theme_ticket_summary
description: >
  Board-level rollup mapping 10 raw Freshdesk tags to 4 investment-lifecycle
  themes. Counts distinct tickets per theme — not per tag — so numbers reflect
  affected tickets.
resource: dbt://titanbay_is/marts/mart_theme_ticket_summary
tags: [mart, theme, board-reporting, tags]
timestamp: 2026-06-17T00:00:00Z
grain: one row per (theme, partner_id, week_start, requester_type)
materialization: table
layer: mart
---

# mart_theme_ticket_summary

Answers "what do investors struggle with?" at a level suitable for board
reporting.

The 10 raw Freshdesk tags are grouped into 4 themes:

| Theme | Tags it covers |
|---|---|
| Identity & Compliance | `kyc`, `onboarding` |
| Documents & Signatures | `documents`, `e-signature` |
| Investment Process | `commitment`, `fund-info`, `payment` |
| Platform & Access | `account`, `portal`, `access` |

A ticket touching tags from two themes is counted once in each theme.
**Do not sum `ticket_count` across themes** for the same time period — a ticket
spanning two themes would be double-counted.

# Schema

| Column | Description |
|---|---|
| `theme` | Internal theme key (e.g. `investment_process`). |
| `theme_label` | Display label (e.g. `Investment Process`). |
| `theme_sort_order` | 1–4, for consistent chart ordering. |
| `partner_id` | FK → dim_partner. |
| `week_start` | Monday of the ISO week. |
| `month_start` | First of the month. |
| `requester_type` | Investor vs RM breakdown within theme. |
| `ticket_count` | Distinct tickets in this theme/partner/week/requester_type combination. |

# Examples

**Board-level view — total affected tickets per theme this year:**
```sql
select theme_label, sum(ticket_count) as tickets
from mart_theme_ticket_summary
where week_start >= '2026-01-01'
group by theme_label, theme_sort_order
order by theme_sort_order
```

**Which theme is growing fastest (last 3 months vs prior 3 months):**
```sql
select theme_label,
       sum(case when week_start >= current_date - interval '90' day then ticket_count end) as recent,
       sum(case when week_start < current_date - interval '90' day
                and week_start >= current_date - interval '180' day then ticket_count end) as prior
from mart_theme_ticket_summary
group by theme_label, theme_sort_order
order by theme_sort_order
```

# Citations

- [fct_tickets](/knowledge/fct_tickets.md) — spine
- [fct_ticket_tags](/knowledge/fct_tickets.md) — raw tag bridge this mart is built from
