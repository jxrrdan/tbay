-- Investing entities — the legal structure through which commitments are made.
-- Each entity belongs to exactly one partner. Grain: one row per entity.
with source as (
    select * from {{ ref('platform_entities') }}
)

select
    entity_id,
    trim(entity_name) as entity_name,
    partner_id,
    lower(trim(entity_type)) as entity_type,
    lower(trim(kyc_status)) as kyc_status
from source
