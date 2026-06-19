---
type: table
title: mart_attribution_health
description: >
  Weekly data-quality monitor tracking partner attribution rates over time.
  Watch unresolved_rate_pct and fallback_rate_pct — if they trend upward,
  something has broken in the data pipeline.
resource: dbt://titanbay_is/marts/mart_attribution_health
tags: [mart, data-quality, monitoring, attribution]
timestamp: 2026-06-17T00:00:00Z
grain: one row per ISO week
materialization: table
layer: mart
---

# mart_attribution_health

A data-quality KPI series. Not used for IS operational reporting — used to
monitor the health of the [partner attribution](/knowledge/concepts/partner_attribution.md)
pipeline over time.

If `unresolved_rate_pct` trends upward, it means more tickets are coming from
emails or labels that the resolution layer can't match — usually because a new
partner's label variants haven't been added to `partner_label_synonyms.csv`.

# Schema

| Column | What it signals |
|---|---|
| `week_start` | Monday of the ISO week. Primary key. |
| `total_tickets` | All tickets created this week. |
| `unresolved_count` | Tickets with no partner attribution at all. |
| `unresolved_rate_pct` | % unresolved. Should trend toward 0. |
| `fallback_count` | Tickets where partner came from the manual label field. |
| `fallback_rate_pct` | % using label fallback. High = new label variants not in synonym map. |
| `unknown_requester_count` | Tickets from emails not found on the platform. |
| `unknown_requester_rate_pct` | % unknown requesters. |
| `internal_requester_count` | Tickets from @titanbay.com / @titanbay.co.uk staff. |
| `internal_requester_rate_pct` | % internal requesters. |

# Examples

**Current baseline rates:**
```sql
select week_start, unresolved_rate_pct, fallback_rate_pct,
       unknown_requester_rate_pct, internal_requester_rate_pct
from mart_attribution_health
order by week_start desc
limit 12
```

# Citations

- [Partner attribution concept](/knowledge/concepts/partner_attribution.md) — explains the attribution chain being monitored
- [fct_tickets](/knowledge/fct_tickets.md) — source of the attribution method flags
