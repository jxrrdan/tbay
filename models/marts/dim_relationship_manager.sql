-- Relationship-manager dimension. Grain: one row per RM.
select
    rm_id,
    rm_name,
    rm_email,
    partner_id,
    partner_name,
    partner_type
from {{ ref('int_relationship_managers__enriched') }}
