-- Investing-entity dimension, with owning partner. Grain: one row per entity.
with entities as (
    select * from {{ ref('stg_platform__entities') }}
),

partners as (
    select * from {{ ref('stg_platform__partners') }}
)

select
    entities.entity_id,
    entities.entity_name,
    entities.entity_type,
    entities.kyc_status,
    entities.partner_id,
    partners.partner_name,
    partners.partner_type
from entities
left join partners on entities.partner_id = partners.partner_id
