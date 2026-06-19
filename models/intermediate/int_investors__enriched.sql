-- Investor flattened with its entity, owning partner, and (optional) RM.
-- Every join here is many-to-one (investor -> entity -> partner; investor ->
-- rm), so the grain stays one row per investor — no fan-out.
with investors as (
    select * from {{ ref('stg_platform__investors') }}
),

entities as (
    select * from {{ ref('stg_platform__entities') }}
),

partners as (
    select * from {{ ref('stg_platform__partners') }}
),

rms as (
    select * from {{ ref('stg_platform__relationship_managers') }}
)

select
    investors.investor_id,
    investors.user_id,
    investors.email,
    investors.full_name,
    investors.country,
    investors.created_at,

    -- Entity context
    investors.entity_id,
    entities.entity_name,
    entities.entity_type,
    entities.kyc_status,

    -- Partner context (via the entity — this is the authoritative partner link
    -- for an investor, since an investor has no direct partner_id of its own)
    entities.partner_id,
    partners.partner_name,
    partners.partner_type,

    -- Relationship-manager context. Null when the investor self-manages.
    investors.relationship_manager_id,
    rms.rm_name,
    rms.rm_email,
    (investors.relationship_manager_id is not null) as is_rm_managed
from investors
left join entities on investors.entity_id = entities.entity_id
left join partners on entities.partner_id = partners.partner_id
left join rms on investors.relationship_manager_id = rms.rm_id
