-- Support tickets raised via the platform. The requester may be an investor
-- OR a relationship manager (resolved downstream). partner_label is a manual,
-- unreliable free-text field (~44% null) and is carried through only as a
-- fallback / audit column. Grain: one row per ticket.
with source as (
    select * from {{ ref('freshdesk_tickets') }}
)

select
    ticket_id,
    -- Normalised to match against investor.email and rm_email.
    lower(trim(requester_email)) as requester_email,
    trim(requester_name) as requester_name,
    trim(subject) as subject,
    lower(trim(status)) as status,
    lower(trim(priority)) as priority,
    cast(created_at as timestamp) as created_at,
    cast(resolved_at as timestamp) as resolved_at,
    tags as tags_raw,
    -- Kept as-is (only emptied-to-null) so the QA layer can judge it honestly.
    nullif(trim(partner_label), '') as partner_label
from source
