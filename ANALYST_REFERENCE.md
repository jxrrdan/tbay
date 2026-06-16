# Analyst Reference — Titanbay IS Support Model

This is your working reference. Start here rather than the README.

---

## Quick-start: which table do I use?

| Question | Table |
|---|---|
| Which investors raise the most tickets? | `mart_investor_ticket_summary` |
| What topics do investors struggle with? | `mart_theme_ticket_summary` |
| Raw tag-level detail per ticket | `fct_ticket_tags` |
| Every ticket with requester and partner resolved | `fct_tickets` |
| Weekly team-wide ticket load vs close calendar | `mart_is_pressure_weekly` |
| Which partners are driving load each week? | `mart_partner_pressure_weekly` |
| What ticket load should we expect from upcoming closes? | `mart_staffing_forecast` |
| How many tickets did each close generate? | `mart_close_ticket_pressure` |
| Is our data quality getting better or worse? | `mart_attribution_health` |
| Look up a specific investor / RM / partner / close | `dim_*` tables |

---

## Marts

### `fct_tickets`
One row per support ticket. The spine — join everything else to this.

| Column | Description |
|---|---|
| `ticket_id` | Freshdesk ticket number |
| `requester_type` | `investor` / `relationship_manager` / `internal` / `unknown` |
| `investor_id` | FK → `dim_investor`. Null unless requester is an investor |
| `rm_id` | FK → `dim_relationship_manager`. Null unless requester is an RM |
| `partner_id` | FK → `dim_partner`. Derived — see `partner_attribution_method` |
| `partner_attribution_method` | How `partner_id` was derived: `investor_email_match` → `rm_email_match` → `partner_label_fallback` → `unresolved` |
| `status` | `open` / `pending` / `resolved` / `closed` |
| `priority` | `low` / `medium` / `high` / `urgent` |
| `created_at` / `resolved_at` | Timestamps. `resolved_at` is null for open tickets |
| `created_week` / `created_month` | Monday-anchored week start and month start (DATE) |
| `is_resolved` | Boolean. Use instead of checking `status` values |
| `is_open` | Boolean. True for `open` and `pending` |
| `resolution_hours` | Decimal hours from creation to resolution. Null if unresolved |
| `investor_email_is_ambiguous` | True if multiple investors share this email (rare; one was selected deterministically) |
| `partner_label` | Raw IS-entered label. **Do not use for analysis** — use `partner_id` instead |

**Things not to do:**
- Do not filter `WHERE requester_type = 'investor'` to get "all investor tickets" and then count by `partner_id` — RM-raised tickets belong to partners too
- Do not trust `partner_label` for aggregation; it has 80 inconsistent variants for 15 partners

---

### `mart_investor_ticket_summary`
One row per investor, including investors with zero tickets. Use this for the "who raises the most" question.

| Column | Description |
|---|---|
| `investor_id` / `full_name` / `email` | Investor identity |
| `partner_name` / `partner_type` | The partner firm this investor belongs to |
| `entity_name` / `entity_type` / `kyc_status` | The investing entity |
| `is_rm_managed` | True if this investor has a relationship manager handling their account |
| `ticket_count` | Total tickets raised directly by this investor (RM-raised excluded) |
| `resolved_count` / `open_count` | Resolved vs currently open |
| `urgent_count` / `high_count` | High-priority breakdown |
| `avg_resolution_hours` / `median_resolution_hours` | Speed of resolution for this investor's tickets |
| `first_ticket_at` / `last_ticket_at` | Tenure as a support user |

**Example — top 10 investors by open ticket backlog:**
```sql
select full_name, partner_name, ticket_count, open_count, urgent_count
from mart_investor_ticket_summary
where ticket_count > 0
order by open_count desc, ticket_count desc
limit 10
```

---

### `mart_theme_ticket_summary`
Board-level rollup of tickets by investment-lifecycle theme. A ticket is counted once per theme it touches — not once per raw tag — so numbers reflect affected tickets.

| Theme | Raw tags it covers |
|---|---|
| Identity & Compliance | `kyc`, `onboarding` |
| Documents & Signatures | `documents`, `e-signature` |
| Investment Process | `commitment`, `fund-info`, `payment` |
| Platform & Access | `account`, `portal`, `access` |

| Column | Description |
|---|---|
| `theme_label` | One of the four themes above |
| `theme_sort_order` | 1–4, for consistent chart ordering |
| `partner_id` | The partner associated with the ticket |
| `week_start` / `month_start` | Calendar grain |
| `requester_type` | Investor vs RM breakdown within theme |
| `ticket_count` | Distinct tickets in this theme/partner/week combination |

**Do not sum `ticket_count` across themes** for the same time period — a ticket touching two themes is counted twice.

**Example — board-level view, total affected tickets per theme this year:**
```sql
select theme_label, sum(ticket_count) as tickets
from mart_theme_ticket_summary
where week_start >= '2026-01-01'
group by theme_label, theme_sort_order
order by theme_sort_order
```

---

### `mart_is_pressure_weekly`
Team-wide weekly time series. Use this to see how ticket volume relates to the close calendar historically and plan forward.

| Column | Description |
|---|---|
| `week_start` | Monday of the ISO week (DATE) |
| `tickets_created` | New tickets opened that week |
| `tickets_high_urgent` | Subset at high or urgent priority |
| `tickets_resolved` | Tickets resolved that week (may include tickets from prior weeks) |
| `closes_scheduled` | Fund closes with `scheduled_close_date` in this week |
| `closes_upcoming` | Of those, closes still in upcoming status |
| `committed_aum_closing_gbp` | Total AUM committed across closes in this week |

---

### `mart_partner_pressure_weekly`
Same as above but split by partner. Use this to see which firm is driving load in any given week.

Grain: one row per (partner, week). Weeks with no tickets and no closes for that partner are excluded.

---

### `mart_staffing_forecast`
One row per upcoming close. Tells you how much ticket load to expect based on what similar closes generated historically.

| Column | Description |
|---|---|
| `fund_name` / `partner_name` | Which close |
| `scheduled_close_date` | The close date |
| `pressure_window_start/end` | ±14-day window around the close (configurable) |
| `historical_close_count` | Number of completed closes this forecast is based on |
| `avg_tickets_per_close` | Mean tickets in the ±14-day window from historical closes |
| `min_tickets_observed` / `max_tickets_observed` | Range for planning a buffer |
| `expected_tickets` | Point estimate (= avg, rounded) |
| `expected_high_urgent_tickets` | Estimated high/urgent subset |
| `no_historical_data` | True = new partner, no track record. Use avg across all partners as a fallback |
| `low_sample_warning` | True = fewer than 3 completed closes. Estimate is less reliable |

**Example — next 8 weeks of expected load:**
```sql
select scheduled_close_date, fund_name, partner_name,
       expected_tickets, min_tickets_observed, max_tickets_observed,
       no_historical_data, low_sample_warning
from mart_staffing_forecast
where pressure_window_end >= current_date
order by scheduled_close_date
```

---

### `mart_close_ticket_pressure`
One row per close (completed and upcoming). Shows how many tickets each close actually generated within the ±14-day window.

**Important:** tickets near overlapping closes from the same partner are counted against both closes. Do not sum `tickets_in_window` across closes and expect it to equal total partner tickets — it won't.

| Column | Description |
|---|---|
| `tickets_in_window` | Tickets from this partner in the ±14-day window |
| `tickets_before_close` / `tickets_on_or_after_close` | Split around the close date |
| `tickets_high_urgent` | High/urgent subset |

---

### `mart_attribution_health`
Weekly data-quality monitor. Track these two columns — if they trend upward something has broken in the data pipeline.

| Column | What it signals |
|---|---|
| `unresolved_rate_pct` | % of tickets with no partner attribution at all. Should trend toward 0 as platform IDs are stamped on tickets |
| `fallback_rate_pct` | % of tickets relying on the manual `partner_label` field. High = IS team not filling it in, or new label variants not in the synonym map |
| `unknown_requester_rate_pct` | % of tickets from emails not found on the platform |
| `internal_requester_rate_pct` | % of tickets from @titanbay.com / @titanbay.co.uk staff |

---

## Dimensions

Quick reference — these are the look-up tables for joining.

| Table | Grain | Key columns |
|---|---|---|
| `dim_investor` | One per investor | `investor_id`, `email`, `entity_id`, `partner_id`, `is_rm_managed` |
| `dim_partner` | One per partner firm | `partner_id`, `partner_name`, `partner_type` |
| `dim_relationship_manager` | One per RM | `rm_id`, `rm_email`, `partner_id` |
| `dim_entity` | One per investing entity | `entity_id`, `entity_type`, `kyc_status`, `partner_id` |
| `dim_fund_close` | One per fund close | `close_id`, `fund_id`, `scheduled_close_date`, `close_status`, `close_week` |

---

## Understanding `requester_type`

Every ticket is classified into one of four types:

| Type | What it means | Counted in investor summaries? |
|---|---|---|
| `investor` | Email matched a registered platform investor | Yes |
| `relationship_manager` | Email matched an RM — they raised the ticket on behalf of a client | No (analyse via partner) |
| `internal` | @titanbay.com or @titanbay.co.uk address — IS team / ops staff | No |
| `unknown` | Email not found anywhere on the platform | No |

RM-raised tickets are attributed to the RM's partner and appear in partner-level views, but are excluded from `mart_investor_ticket_summary` to avoid inflating individual investor counts.

---

## Viewing data lineage

Run `dbt docs generate && dbt docs serve` from the project root. This opens an interactive DAG showing how every model connects to every other. The diagram is generated directly from the code and is always accurate.

For a static view, the dependency order is:

```
seeds (raw CSVs)
  └── staging models (stg_*)
        └── intermediate models (int_*)
              └── dimensions (dim_*)
              └── fct_tickets ──────────────┐
              └── fct_ticket_tags ──────────┤
                                             ├── mart_investor_ticket_summary
                                             ├── mart_theme_ticket_summary
                                             ├── mart_is_pressure_weekly
                                             ├── mart_partner_pressure_weekly
                                             ├── mart_attribution_health
              dim_fund_close ───────────────┤
                                             ├── mart_close_ticket_pressure
                                             └── mart_staffing_forecast
```
