---
type: concept
title: Partner Attribution
description: >
  How every ticket is linked to a partner firm, in trust order from most to
  least reliable. Recorded in fct_tickets.partner_attribution_method.
tags: [concept, partner, attribution, data-quality]
timestamp: 2026-06-17T00:00:00Z
implemented_in: models/intermediate/int_tickets__requester_resolution.sql
---

# Partner Attribution

After [entity resolution](/knowledge/concepts/entity_resolution.md) classifies
a ticket's requester, the next step is linking the ticket to a partner firm.
The attribution method used is recorded in `fct_tickets.partner_attribution_method`.

## The trust chain

```
1. investor_email_match   — investor's entity → partner (most reliable)
2. rm_email_match         — RM's owning partner
3. partner_label_fallback — IS-entered free text field, normalised via synonym map
4. unresolved             — no partner can be determined
```

The chain is evaluated left-to-right and the first match wins.

## Why the label is last resort

The `partner_label` field on Freshdesk tickets is manually entered by IS staff
and is:
- Null on ~44% of tickets
- Has **80 distinct string variants** for just 15 partners (e.g. `Clearwater Direct`,
  `CLEARWATER DIRECT`, `clearwater direct`, `Clearwater D`, `Clearwater`)

It is mapped via a generated synonym seed (`seeds/partner_label_synonyms.csv`)
that assigns each variant to the correct `partner_id` using a unique keyword
per partner. All 80 observed variants resolve cleanly.

The label is used as a *fallback*, not a primary source, because email-derived
attribution is authenticated at registration while the label is free text.

## Current attribution breakdown

| Method | Tickets | % |
|---|---|---|
| `investor_email_match` | 1,060 | 53.0% |
| `rm_email_match` | 760 | 38.0% |
| `partner_label_fallback` | 47 | 2.4% |
| `unresolved` | 133 | 6.7% |

The 133 unresolved are: 100 internal `@titanbay` tickets (no label, no email
match possible) + 33 unknown-requester tickets with no label filled in.

## Monitoring

[mart_attribution_health](/knowledge/mart_attribution_health.md) tracks
`unresolved_rate_pct` and `fallback_rate_pct` over time. If new partners
onboard and their label variants aren't added to the synonym seed, fallback
rate will rise before unresolved rate does.

## The long-term fix

Stamp `investor_id`, `rm_id`, and `partner_id` as Freshdesk custom fields at
ticket creation time. This retires the entire resolution and attribution chain
and makes attribution 100% reliable without email matching or label synonyms.

# Citations

- [Entity resolution](/knowledge/concepts/entity_resolution.md) — the step before attribution
- [mart_attribution_health](/knowledge/mart_attribution_health.md) — monitors these rates over time
- [fct_tickets](/knowledge/fct_tickets.md) — partner_id and partner_attribution_method columns
