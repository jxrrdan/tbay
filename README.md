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
| Is a ticket from an investor, an RM, or someone we can't identify? | `fct_tickets.requester_type` |
| Which partner does a ticket belong to (without trusting the manual label)? | `fct_tickets.partner_id` (+ `partner_attribution_method`) |
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

---

## 4. The core decision: entity resolution across requester types

The brief hints that *"the data contains more than one type of person raising
tickets."* It does — a `requester_email` can belong to:

1. an **investor** (matches `platform_investors.email`),
2. a **relationship manager** raising a ticket on a client's behalf (matches
   `relationship_managers.email`), or
3. **neither** — an ex-user, a typo, or an internal/forwarded address.

`int_tickets__requester_resolution` classifies every ticket into exactly one of
`investor` / `relationship_manager` / `unknown`, and from that derives the
partner. Key decisions:

**Precedence (investor-first).** If an email somehow matches both an investor and
an RM, we classify it as an investor and set `requester_matched_both = true` for
audit. Investor-first keeps the headline "which investors raise the most tickets"
question answerable; the flag means an analyst can re-cut the other way in one
line if the data warrants it.

**Partner attribution by trust, not by the manual label.** The IS-entered
`partner_label` is null ~44% of the time and "not always consistent," so we do
**not** trust it as the primary source. Instead `partner_id` is derived in trust
order:

```
investor's partner  →  RM's partner  →  exact partner-label name match  →  null
```

`partner_attribution_method` records which rung was used, so data quality is
measurable, not hidden. The raw label is carried through on `fct_tickets` for
audit only.

**Grain safety (the one-to-many trap).** A naive `tickets ⋈ investors ON email`
fans out the moment one email maps to two investor rows (duplicate
registrations). We prevent this by collapsing the lookups to **one row per email**
(deterministically: earliest-registered investor wins) *before* joining, and
exposing `investor_email_is_ambiguous` / `rm_email_is_ambiguous` so the collapsed
ambiguity stays visible. Result: `fct_tickets` is provably **one row per
ticket** — verified by a `unique` test on `ticket_id`.

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
  The window is configurable via `--vars 'close_pressure_window_days: 21'`.

> Caveat documented in-model: close windows for the same partner can overlap, so
> a ticket may be attributed to more than one close. This is load *attribution*,
> not a partition — don't sum `tickets_in_window` across closes.

---

## 6. Data quality issues and how they're handled

| Issue (from the data dictionary / expected in the data) | Handling |
|---|---|
| `partner_label` ~44% null and inconsistent | Demoted to last-resort fallback + audit column; partner derived from email-resolved identity instead. |
| `relationship_manager_id` ~41% null | Treated as a real signal — the investor self-manages — surfaced as `is_rm_managed`, not an error. |
| `resolved_at` ~42% null | Genuine open/unresolved tickets; `is_resolved` flag + `resolution_hours` only computed when resolved. |
| Email casing / whitespace differences across systems | Normalised to `lower(trim())` in staging so joins are reliable. |
| Same email → multiple investors (duplicate registrations) | Deduplicated to one investor per email; ambiguity flagged, grain protected. |
| Requester email matching neither investor nor RM | Explicit `unknown` class rather than a silent drop or bad join. |
| Inconsistent category values (status/priority/type/KYC) | `accepted_values` tests (severity `warn`) surface drift without blocking the build. |
| Orphaned foreign keys | `relationships` tests (severity `warn`) quantify any orphans. |

> Tests are split by intent: **primary-key integrity** (`unique`, `not_null`)
> runs as `error`; **discovery tests** (`accepted_values`, `relationships`) run as
> `warn`, so the build completes and the warnings *document* the data's real state
> rather than halting the pipeline. Run `dbt test` to get the live counts.

---

## 7. Assumptions

- **Email is the trustworthy identity key.** No shared ticket↔investor id exists,
  so email is the only available link. Normalisation makes it reliable enough.
- **Investor-first precedence** when an email matches both types (see §4).
- **An investor's partner comes via their entity** — investors have no direct
  `partner_id`, and `entity.partner_id` is authoritative.
- **`mart_investor_ticket_summary` counts only investor-raised tickets.** RM- and
  unknown-raised tickets are analysed via `fct_tickets` / partner views, so the
  per-investor counts aren't inflated by tickets the investor didn't raise.
- **Monday-anchored weeks** throughout, for consistency between the ticket series
  and the close calendar.
- **±14 days** is a reasonable default close-pressure window; it is a `var`, so
  it's trivially tunable once the real lead/lag is measured.

---

## 8. How to run

```bash
pip install -r requirements.txt          # dbt-core + dbt-duckdb, nothing else

# place the six CSVs in seeds/ (filenames matching the table names), then:
export DBT_PROFILES_DIR=$(pwd)
dbt build                                # seeds → models → tests, end to end
```

The project has **no external package dependencies** (only built-in generic
tests are used), so it runs with no network access beyond the pip install.

Everything materialises into a local `titanbay_is.duckdb` file — no warehouse
credentials needed. The SQL is standard dbt and ports to BigQuery with only the
profile changed. (The DuckDB-specific bits — `qualify`, `unnest(string_split(...))`,
`epoch()` — have direct BigQuery equivalents.)

---

## 9. What I'd build next

- **Partner-level pressure** cut of `mart_is_pressure_weekly` to see which
  partners drive load.
- **Tag taxonomy / theme rollup** — map raw tags to a small set of themes
  (documents, onboarding, technical, commitment) for cleaner "what they struggle
  with" reporting.
- **Incremental `fct_tickets`** keyed on `ticket_id` once volume grows (the model
  is already deterministic, so it's a config change).
- **A predictive layer** — regress weekly tickets on upcoming committed AUM /
  close count to produce an actual staffing forecast.
- **A `requester_resolution` monitoring exposure** tracking the `unknown` rate
  over time as a data-health KPI.

---

## 10. How I worked with AI tools

This model was built collaboratively with an AI coding assistant (Claude). I used
it to scaffold the dbt project and boilerplate (staging models, YAML, tests) so I
could spend my time on the parts that need judgement: the requester-resolution
precedence rules, the grain-safety design for duplicate emails, the trust-ordered
partner attribution, and how to frame "pressure" as something forecastable from
the close calendar. The AI accelerated the mechanical work; the architecture and
the trade-offs are the deliberate decisions described above.

---

## 11. Reflection — the ideal long-term fix

The root problem is that **Freshdesk has no reliable foreign key back to the
platform** — tickets are stitched on by email and patched with a manual,
half-populated `partner_label`. The durable fix is to **stamp the platform
`investor_id` (and, where applicable, `rm_id` / `partner_id`) onto the ticket at
creation time**, by passing the authenticated user's identity from the platform
into Freshdesk as custom fields rather than relying on whatever email the
requester happens to type. That single upstream change removes the entire
resolution layer, eliminates the `unknown`/duplicate-email ambiguity, and retires
the unreliable `partner_label` — making every downstream model both simpler and
trustworthy.
