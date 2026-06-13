-- Investor dimension — the enriched investor with entity, partner and RM
-- context already resolved upstream. Grain: one row per investor.
select
    investor_id,
    user_id,
    email,
    full_name,
    country,
    created_at,

    entity_id,
    entity_name,
    entity_type,
    kyc_status,

    partner_id,
    partner_name,
    partner_type,

    relationship_manager_id,
    rm_name,
    rm_email,
    is_rm_managed
from {{ ref('int_investors__enriched') }}
