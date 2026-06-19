-- Relationship managers employed by partner organisations. RMs can raise
-- tickets on behalf of their investors, so their email is a key join surface
-- for requester resolution. Grain: one row per RM.
with source as (
    select * from {{ ref('platform_relationship_managers') }}
)

select
    rm_id,
    partner_id,
    trim(name) as rm_name,
    -- Normalised for joining against ticket requester_email. The raw casing /
    -- whitespace is dropped here so every downstream match uses one form.
    lower(trim(email)) as rm_email
from source
