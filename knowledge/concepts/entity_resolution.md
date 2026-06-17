---
type: concept
title: Entity Resolution
description: >
  How a Freshdesk ticket's requester email is matched to a known person on the
  platform and classified into one of four requester types.
tags: [concept, entity-resolution, requester, email-matching]
timestamp: 2026-06-17T00:00:00Z
implemented_in: models/intermediate/int_tickets__requester_resolution.sql
---

# Entity Resolution

A Freshdesk ticket has no `investor_id` or `partner_id` — the only link to the
platform is the requester's email address. Entity resolution is the process of
turning that email into a structured identity.

## The four-way classification

Profiling the data revealed four distinct requester populations, not two as the
original brief implied:

| Type | How identified | % of tickets |
|---|---|---|
| `investor` | Email matches `platform_investors.email` | 53% |
| `relationship_manager` | Email matches `platform_relationship_managers.email` | 38% |
| `internal` | Email domain is `@titanbay.com` or `@titanbay.co.uk` | 5% |
| `unknown` | Email not found anywhere on the platform | 4% |

The `internal` class is the one the data dictionary misses. Without catching it
explicitly, those 100 tickets fall into `unknown` and inflate that bucket. They
represent IS team members raising tickets on behalf of investors — identifiable
by email domain but not attributable to a specific investor without further work.

## How the matching works

Three left joins run simultaneously against the ticket table:

```
tickets
  LEFT JOIN investors ON requester_email = investor.email     → investor match
  LEFT JOIN rms       ON requester_email = rm.email           → RM match
  LEFT JOIN labels    ON partner_label  = synonym.label_norm  → label match
```

The classification CASE then evaluates in precedence order:
1. If investor matched → `investor`
2. Else if RM matched → `relationship_manager`
3. Else if email domain is `@titanbay.*` → `internal`
4. Else → `unknown`

## Grain protection

Email lookups are deduplicated to **one row per email** before joining, using
`QUALIFY row_number() = 1`. This prevents a ticket from fanning out if two
investors share an email address. In the current data all 1,253 investor emails
are unique, but the guard is in place for future data.

## Precedence rule

If an email matches both an investor and an RM (zero cases in current data),
the ticket is classified as `investor`. This is conservative — it avoids
suppressing investor-behaviour signal. The `requester_matched_both` flag
surfaces any such case.

# Citations

- [Requester types](/knowledge/concepts/requester_types.md) — what each type means for analysis
- [Partner attribution](/knowledge/concepts/partner_attribution.md) — how partner_id is derived from the resolved type
- [fct_tickets](/knowledge/fct_tickets.md) — where the resolved type lands
