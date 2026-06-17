# Titanbay — Investor Services Support Analytics Model

A layered analytics model that turns six raw extracts (Freshdesk + the platform
warehouse) into a clean, analyst-ready view of **who raises support tickets, what
they struggle with, and when the Investor Services (IS) team is likely to be
under pressure.**

---

## 1. The business problem

The Head of Investor Services asked for two things:

1. **Behaviour** — *"Which investors are raising the most support tickets, and
   what patterns exist in that behaviour?"*
2. **Resourcing** — *"Help me anticipate when the team is likely to be under more
   pressure than usual, so we can plan ahead instead of firefighting."*

Today, tickets live in Freshdesk in isolation. A ticket has a requester email and
a free-text subject, but **nothing structurally ties it back to the investor, the
entity they invest through, the partner they belong to, or the fund-close calendar
that drives activity on the platform.** So the IS team can't say "investor X has
raised 14 tickets this quarter, mostly about documents" or "ticket volume spikes
in the two weeks before a close."

### What an analyst can do now that they couldn't before

After this model, an analyst can answer, in plain SQL against a handful of tables:

| Question | Where to look |
|---|---|
| Which investors raise the most tickets? Of what priority? How fast are they resolved? | `mart_investor_ticket_summary` |
| What do investors struggle with (themes/tags)? | `fct_ticket_tags` |
| Is a ticket from an investor, an RM, an internal Titanbay person, or someone unresolvable? | `fct_tickets.requester_type` |
| Which partner does a ticket belong to (without trusting the manual label)? | `fct_tickets.partner_id` + `partner_attribution_method` |
| How has weekly ticket load tracked the fund-close calendar? | `mart_is_pressure_weekly` |
| How many tickets does a typical close generate, and what's coming up? | `mart_close_ticket_pressure` |

---

## 2. The data and how the pieces connect

Six tables, two source systems:

```
                 platform_partners (15)
                  ▲      ▲        ▲
                  │      │        │
   relationship_managers │     platform_fund_closes (153)
        (42)             │        (scheduled_close_date → pressure signal)
          ▲              │
          │          platform_entities (772)
          │              ▲
          │              │
        platform_investors (1,253)
        (email, relationship_manager_id ~41% null)
                  │
                  │  requester_email / rm_email
                  ▼
          freshdesk_tickets (2,000)
          (requester_email, tags, partner_label ~44% null)
```

The **only** link between a Freshdesk ticket and the platform world is the
**requester's email address**. There is no `investor_id` or `partner_id` on a
ticket. Reconstructing that link is the core of the task.

---

## 3. Modelling approach

A conventional **staging → intermediate → marts** dbt layering. Each layer has one
job, so you can follow the logic without reading every line of SQL.

### Staging (`models/staging/`) — one model per source, light cleaning only
Type casting, trimming, and — critically — **normalising every email and
category to `lower(trim(...))`**. Email is the join key for the entire model, so
casing/whitespace inconsistencies are removed once, here, rather than in every
downstream join.

### Intermediate (`models/intermediate/`) — resolve relationships and identity
- `int_investors__enriched` — investor + entity + partner + RM, flattened. All
  joins are many-to-one, so grain stays **one row per investor**.
- `int_relationship_managers__enriched` — RM + partner.
- `int_tickets__requester_resolution` — **the analytical heart** (see §4).

### Marts (`models/marts/`) — dimensional, analyst-facing
- Dimensions: `dim_partner`, `dim_relationship_manager`, `dim_entity`,
  `dim_investor`, `dim_fund_close`.
- Facts: `fct_tickets` (one row per ticket), `fct_ticket_tags` (one row per
  ticket × tag).
- Analysis marts: `mart_investor_ticket_summary` (Q1),
  `mart_is_pressure_weekly` and `mart_close_ticket_pressure` (Q2).

### Seeds (`seeds/`)
- Six raw CSV extracts, loaded as seeds so `dbt build` is self-contained.
- `partner_label_synonyms.csv` — a generated mapping of the 80 observed
  `partner_label` variants to the 15 canonical partner IDs (see §5).

---

## 4. The core decision: entity resolution across requester types

The brief hints that *"the data contains more than one type of person raising
tickets."* It does — after profiling, a `requester_email` can belong to:

1. **investor** — matches `platform_investors.email` (1,060 tickets, 53%)
2. **relationship_manager** — matches `platform_relationship_managers.email`
   (760 tickets, 38%)
3. **internal** — `@titanbay.com` or `@titanbay.co.uk` address (100 tickets, 5%).
   The requester_name for these is often a different person's name, suggesting IS
   team members are raising tickets on behalf of investors rather than for
   themselves. No partner attribution is possible from email alone.
4. **unknown** — consumer personal email not found on the platform (80 tickets,
   4%): gmail, yahoo, outlook, icloud, hotmail addresses. Likely ex-users or
   personal addresses used in Freshdesk.

`int_tickets__requester_resolution` classifies every ticket into exactly one of
these four types, and from that derives the partner. Key decisions:

**Precedence (investor-first).** If an email matches both an investor and an RM,
we classify as investor (this never fires in the current data — zero overlap —
but the logic protects future data). `requester_matched_both` flags any such case.

**Partner attribution by trust order, not by the manual label.** The IS-entered
`partner_label` is null ~44% of the time and has **80 distinct string variants**
for just 15 partners (all of `Clearwater Direct`, `CLEARWATER DIRECT`,
`clearwater direct`, `Clearwater D`, `Clearwater`, etc. are in the data). We do
**not** use it as a primary source. Instead `partner_id` is derived in trust order:

```
investor email  →  RM email  →  label synonym lookup  →  null
```

The synonym lookup uses a generated seed (`partner_label_synonyms.csv`) that maps
every observed label variant to the correct `partner_id` via a unique keyword per
partner (e.g., anything containing `clearwater` → Clearwater Direct). All 80
variants resolved cleanly with zero unmatched entries.

**Final partner attribution result:**

| Method | Tickets | % |
|---|---|---|
| investor_email_match | 1,060 | 53.0% |
| rm_email_match | 760 | 38.0% |
| partner_label_fallback | 47 | 2.4% |
| unresolved | 133 | 6.7% |

The 133 unresolved are: all 100 internal tickets (no label) + 33 consumer-email
tickets with no label. `partner_attribution_method` records this for auditing.

**Grain safety (the one-to-many trap).** A naive `tickets ⋈ investors ON email`
fans out the moment one email maps to two investor rows. We prevent this by
collapsing lookups to **one row per email** (earliest-registered wins, then id)
*before* joining. In the current data all 1,253 investor emails are unique and
there is zero investor/RM email overlap, so this never actually fires — but
`investor_email_is_ambiguous` / `rm_email_is_ambiguous` surface any future
collapse. Result: `fct_tickets` is provably **one row per ticket** — verified by
a `unique` test on `ticket_id`.

---

## 5. Anticipating pressure

Each fund close has a `scheduled_close_date`, and platform activity (and therefore
support load) clusters around closes. Two complementary models:

- **`mart_is_pressure_weekly`** — a team-wide weekly series with tickets created,
  high/urgent tickets, tickets resolved, closes scheduled, and committed AUM
  closing, all on one row per ISO week. Plot ticket volume against closes and the
  historical relationship (and any lead/lag) is visible immediately.
- **`mart_close_ticket_pressure`** — one row per close, counting the partner's
  tickets within ±14 days of the close (split before/after). This converts the
  *known* schedule of upcoming closes into a forward estimate:
  *avg tickets-per-completed-close × upcoming closes ≈ expected future load.*
  Foxmore and Aldgate funds show the highest ticket density per close (12–15
  tickets in the ±14-day window). The window is configurable via
  `--vars 'close_pressure_window_days: 21'`.

> Caveat documented in-model: close windows for the same partner can overlap, so
> a ticket may be attributed to more than one close. This is load *attribution*,
> not a partition — don't sum `tickets_in_window` across closes.

---

## 6. Data quality issues found and how they're handled

| Issue | Handling |
|---|---|
| `partner_label` ~44% null and 80 distinct variants of 15 partner names | Generated a keyword-based synonym seed mapping all 80 variants to canonical `partner_id`. Used as last-resort fallback only; partner_attribution_method records when it was used. |
| `relationship_manager_id` ~41% null | Treated as a real signal — the investor self-manages — surfaced as `is_rm_managed`, not an error. |
| `resolved_at` ~42% null | Genuine open/unresolved tickets; `is_resolved` flag + `resolution_hours` only computed when resolved. |
| 100 tickets from `@titanbay.com`/`@titanbay.co.uk` with mismatched requester names | Classified as `internal` (IS team raising tickets on behalf of investors). No partner attribution currently possible; noted as a gap. |
| 80 tickets from personal/consumer emails (gmail, outlook, etc.) | Classified as `unknown` with explicit flag. Not silently dropped. |
| Email casing / whitespace differences across systems | Normalised to `lower(trim())` in staging for all join keys. |
| **Fund close ordering anomaly**: 7 funds where `close_number` doesn't match chronological order of `scheduled_close_date` (e.g. Stirling Private Equity Fund 2023 has close 1 dated 2026-11-02 but close 2 dated 2026-03-23). | We trust `scheduled_close_date` as the authoritative date for calendar analysis; `close_number` is likely a data-entry error. `dim_fund_close` exposes both. A source-level fix is needed (see §11). |
| Inconsistent category values (status/priority/type/KYC) | `accepted_values` tests (severity `warn`) surface drift without blocking the build. All current values are in range. |
| Orphaned foreign keys | `relationships` tests (severity `warn`) quantify any orphans. All currently clean. |

> Tests are split by intent: **primary-key integrity** (`unique`, `not_null`)
> runs as `error`; **discovery tests** (`accepted_values`, `relationships`) run as
> `warn`, so the build completes and the warnings *document* the data's real state
> rather than halting the pipeline. All 80 tests pass on the current data.

---

## 7. Assumptions

- **Email is the trustworthy identity key.** No shared ticket↔investor id exists,
  so email is the only available link. Normalisation makes it reliable enough.
- **Investor-first precedence** when an email matches both types (see §4). In
  practice this never fires but the logic is in place.
- **An investor's partner comes via their entity** — investors have no direct
  `partner_id`, and `entity.partner_id` is authoritative.
- **`scheduled_close_date` is more reliable than `close_number`** for ordering
  closes within a fund, given the ordering anomaly in 7 funds.
- **`mart_investor_ticket_summary` counts only investor-raised tickets.** RM-
  and internal-raised tickets are analysed via `fct_tickets` / partner views,
  so the per-investor counts aren't inflated by tickets the investor didn't raise.
- **Monday-anchored weeks** throughout, for consistency between the ticket series
  and the close calendar.
- **±14 days** is a reasonable default close-pressure window; it is a `var`, so
  it's trivially tunable once the real lead/lag is measured from completed closes.
- **Internal tickets are IS/ops staff** — the mismatched requester name
  (`jordan.thomas@titanbay.com` with name `Shaun Webb`) suggests staff raise
  tickets on behalf of investors. These are excluded from investor-behaviour
  analysis and flagged rather than silently classified as `unknown`.

---

## 8. What the data shows

**Requester behaviour:** The top investors raise 17–19 tickets each. Joan Pollard
(Norbury) and Melissa Wood (Pemberton) lead with 19 tickets each. The highest-
ticket investors tend to have significant open backlogs (8–11 open tickets),
suggesting slow resolution is a systemic issue — not just isolated to one investor.
Median resolution time is **168 hours (~7 days)**; the average is slightly higher
at 175 hours.

**Topic patterns (tags):** The tag distribution is remarkably flat — account,
commitment, documents, onboarding, kyc, e-signature, fund-info, payment, portal,
and access each appear ~360–410 times. This suggests support load is spread across
the entire investment lifecycle, not concentrated in one area, which makes it
harder to solve with a single product fix.

**RM-raised tickets:** Jessica White (Aldgate, 59 tickets) and Gregory Robinson
(Foxmore, 55 tickets) are the highest-volume RM requesters. High RM volume at a
partner may indicate either a high-volume partner or one whose investors are less
self-sufficient.

**Pressure signals:** Foxmore and Aldgate funds generate the most tickets per
close (12–15 in a ±14-day window). Weeks with scheduled closes tend to have more
high/urgent tickets. The `mart_is_pressure_weekly` series makes this visible for
historical validation and forward planning.

---

## 9. How to run

```bash
pip install -r requirements.txt          # dbt-core + dbt-duckdb, nothing else

# place the six raw CSVs in seeds/ (filenames matching the table names), then:
export DBT_PROFILES_DIR=$(pwd)
dbt build                                # seeds → models → tests, end to end
```

The project has **no external package dependencies** (only built-in generic
tests are used), so it runs with no network access beyond the pip install.
Everything materialises into a local `titanbay_is.duckdb` file — no warehouse
credentials needed. The SQL is standard dbt and ports to BigQuery with only the
profile changed.

---

## 10. Data dictionary discrepancies

The PDF data dictionary is accurate on structure (column names, types, row counts,
null rates, enumerated values) but has two places where the description doesn't
match the actual data:

**`close_number` is not reliably chronological.**
The dictionary defines it as "Sequential close number within the fund (1 = first
close, 2 = second, etc.)", implying it is ordered by `scheduled_close_date`. In
practice, **7 funds** have `close_number` values that don't match date order — for
example, Stirling Private Equity Fund 2023 has close 1 dated 2026-11-02 but close
2 dated 2026-03-23. Any model that treats `close_number` as a chronological rank
will silently produce wrong results for those funds. We use `scheduled_close_date`
as the authoritative ordering key throughout and treat `close_number` as a label
only (see §6).

**The `freshdesk_tickets` description omits the internal requester class.**
The dictionary says tickets are raised by "investors or their representatives."
This frames the requester population as a two-way split (investor / RM). In the
actual data, **100 tickets (5%)** come from `@titanbay.com` and `@titanbay.co.uk`
addresses — Titanbay's own staff. These are a distinct third class with different
handling requirements: they can't be attributed to an investor or partner via email
alone, and they should probably be excluded from investor-behaviour reporting
altogether. Without reading the data dictionary sceptically, they would fall into
`unknown` and silently inflate that bucket.

---

## 11. What was built (beyond the initial brief)

The two core questions (investor behaviour, pressure anticipation) were answered
by `mart_investor_ticket_summary` and the `mart_is_pressure_weekly` /
`mart_close_ticket_pressure` pair. Beyond that, five additional models were built
to make the output production-grade:

- **`mart_partner_pressure_weekly`** — per-partner weekly ticket load alongside
  close activity. Reveals which partner firm is driving pressure in any given week,
  not just the team total.
- **`mart_theme_ticket_summary`** — maps the 10 raw Freshdesk tags to 4 investment-
  lifecycle themes (Identity & Compliance, Documents & Signatures, Investment
  Process, Platform & Access) for board-level reporting. Counts distinct tickets
  per theme, not per tag, so a ticket touching two themes is counted once in each.
- **`mart_attribution_health`** — weekly data-quality KPI series tracking
  `unresolved_rate_pct` and `fallback_rate_pct` over time. Provides an early
  warning if the partner synonym map stops covering new label variants.
- **`mart_staffing_forecast`** — forward load estimate per upcoming close, based
  on each partner's historical avg tickets per close. Flags new partners
  (`no_historical_data`) and low-sample estimates (`low_sample_warning` for
  fewer than 3 completed closes).
- **Incremental `fct_tickets`** — the fact table uses a merge strategy on
  `ticket_id` with a 3-day lookback window, so it is safe for production
  incremental runs from day one without a full rebuild.
- **Cross-adapter macros** (`macros/cross_db_utils.sql`) — all date arithmetic,
  median approximation, and array unnesting are dispatched through adapter-aware
  macros. The project runs on DuckDB locally and on BigQuery in production with
  only a profile change.

### What remains as genuine future work

- **Internal ticket attribution** — the 100 `@titanbay.com` tickets cannot be
  attributed to a specific investor or partner from email alone. Working with the
  IS team to understand the naming pattern (e.g. `jordan.thomas@titanbay.com`
  raising a ticket named for a different person) could recover this 5% for
  investor-behaviour analysis.
- **Stamp platform IDs at ticket creation** — the long-term structural fix
  described in §13. Until then, all partner attribution carries the ambiguity
  described in §4.

---

## 12. How I worked with AI tools

This model was built collaboratively with an AI coding assistant (Claude). I used
it to scaffold the dbt project and boilerplate (staging models, YAML, tests) so I
could spend my time on the parts that need judgement: the requester-resolution
precedence rules, the four-way requester classification (including the discovery
that 5% of tickets are Titanbay-internal staff, not investor-unknown), the grain-
safety design for email deduplication, and the trust-ordered partner attribution.
I also used it to generate the `partner_label_synonyms` seed programmatically
from the actual 80 label variants found in the data. The architecture, trade-offs,
and documented decisions above are the deliberate choices I made throughout.

---

## 13. Reflection — the ideal long-term fix

The root problem is that **Freshdesk has no reliable foreign key back to the
platform** — tickets are stitched by email and patched with a manual,
inconsistently-entered `partner_label`. Two durable fixes:

1. **Stamp platform identity onto every ticket at creation time.** When the
   Titanbay platform opens a Freshdesk ticket (or a user does so through a
   platform-integrated flow), pass the authenticated `investor_id`,
   `relationship_manager_id`, and `partner_id` as Freshdesk custom fields. This
   retires the entire resolution layer and makes the attribution 100% reliable.

2. **Fix the `close_number`/`scheduled_close_date` ordering inconsistency at the
   source** — either enforce a constraint that close dates must be monotonically
   increasing with close number, or treat `close_number` as a label rather than
   an ordering key and rely on `scheduled_close_date` for all date logic. Seven
   funds currently have mismatched orderings, which will silently produce wrong
   results in any downstream model that assumes the two columns agree.
