-- Partner dimension. Grain: one row per partner.
select
    partner_id,
    partner_name,
    partner_type
from {{ ref('stg_platform__partners') }}
