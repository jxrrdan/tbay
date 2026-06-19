---
type: concept
title: Requester Types
description: >
  The four classes of Freshdesk ticket requester and what each means for
  analysis. Controls which tables include or exclude which tickets.
tags: [concept, requester-type, investor, relationship-manager, internal]
timestamp: 2026-06-17T00:00:00Z
---

# Requester Types

Every ticket in `fct_tickets` carries a `requester_type` value. Understanding
what each type means determines which tables and filters to use for a given
question.

## The four types

### `investor`
Email matched a registered platform investor. This is the primary population
for investor-behaviour analysis. Counted in
[mart_investor_ticket_summary](/knowledge/mart_investor_ticket_summary.md).

### `relationship_manager`
Email matched a relationship manager. The RM raised the ticket on behalf of
one of their clients — the ticket is not a direct investor action. These
tickets are **excluded from mart_investor_ticket_summary** to avoid inflating
individual investor counts, but they are attributed to the RM's partner and
appear in all partner-level views.

### `internal`
Email domain is `@titanbay.com` or `@titanbay.co.uk`. These are Titanbay IS
team or ops staff members raising tickets. In many cases the requester name
on the ticket is a different person's name, suggesting the IS team is raising
tickets on behalf of investors. No partner attribution is possible from the
email alone. Excluded from investor and partner analysis.

### `unknown`
Email not found anywhere on the platform — personal/consumer addresses (gmail,
outlook, icloud, hotmail), ex-users, or possible typos. 80 tickets in the
current data. Excluded from investor analysis. Some have a `partner_label`
filled in, which enables partial attribution.

## What to use for which question

| Question | Filter |
|---|---|
| Investor-raised tickets only | Use `mart_investor_ticket_summary` — it handles this |
| All tickets attributable to a partner | Use `fct_tickets` with `partner_id is not null` — includes RM-raised |
| IS team activity | `WHERE requester_type = 'internal'` |
| Tickets the model cannot attribute | `WHERE partner_attribution_method = 'unresolved'` |

## Common mistake

Filtering `WHERE requester_type = 'investor'` and then grouping by `partner_id`
to get "tickets per partner" **undercounts** — it misses the 38% of tickets
raised by RMs on behalf of their partner's clients. Always use `partner_id`
directly (which captures all attributable tickets regardless of requester type)
for partner-level volume analysis.

# Citations

- [Entity resolution](/knowledge/concepts/entity_resolution.md) — how requester_type is determined
- [Partner attribution](/knowledge/concepts/partner_attribution.md) — how partner_id is derived from requester_type
- [fct_tickets](/knowledge/fct_tickets.md) — requester_type column
