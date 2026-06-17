---
type: index
title: Titanbay IS Support Analytics
description: >
  Knowledge bundle for the Titanbay Investor Services support analytics model.
  Covers every analyst-facing table and the core concepts behind the data.
tags: [titanbay, investor-services, dbt, support-analytics]
timestamp: 2026-06-17T00:00:00Z
---

# Titanbay IS Support Analytics

This bundle documents the dbt analytics model that connects Freshdesk support
tickets to the Titanbay platform (investors, entities, partners, fund closes).

## Start here

| If you want to... | Go to |
|---|---|
| Find which investors raise the most tickets | [mart_investor_ticket_summary](/knowledge/mart_investor_ticket_summary.md) |
| Understand what investors struggle with | [mart_theme_ticket_summary](/knowledge/mart_theme_ticket_summary.md) |
| See weekly ticket load vs the close calendar | [mart_is_pressure_weekly](/knowledge/mart_is_pressure_weekly.md) |
| See which partners drive load each week | [mart_partner_pressure_weekly](/knowledge/mart_partner_pressure_weekly.md) |
| Forecast tickets from upcoming closes | [mart_staffing_forecast](/knowledge/mart_staffing_forecast.md) |
| See how many tickets each close generated | [mart_close_ticket_pressure](/knowledge/mart_close_ticket_pressure.md) |
| Monitor data quality over time | [mart_attribution_health](/knowledge/mart_attribution_health.md) |
| Query raw tickets with partners resolved | [fct_tickets](/knowledge/fct_tickets.md) |

## Key concepts

- [Entity resolution](/knowledge/concepts/entity_resolution.md) — how a ticket email becomes an investor, RM, internal, or unknown
- [Partner attribution](/knowledge/concepts/partner_attribution.md) — how every ticket is linked to a partner firm
- [Requester types](/knowledge/concepts/requester_types.md) — the four classes of ticket requester and what they mean for analysis
