-- Ticket-tag bridge. Explodes the comma-separated `tags` field to one row per
-- ticket/tag, so an analyst can answer "what do investors struggle with?"
-- without parsing strings. Grain: one row per ticket x tag.
with resolved as (
    select * from {{ ref('int_tickets__requester_resolution') }}
),

exploded as (
    select
        ticket_id,
        investor_id,
        rm_id,
        partner_id,
        requester_type,
        created_at,
        -- split on comma, then normalise each fragment
        lower(trim(unnest(string_split(tags_raw, ',')))) as tag
    from resolved
    where tags_raw is not null and trim(tags_raw) <> ''
)

select
    ticket_id,
    investor_id,
    rm_id,
    partner_id,
    requester_type,
    created_at,
    tag
from exploded
where tag <> ''
