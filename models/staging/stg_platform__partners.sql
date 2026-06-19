-- Partner organisations Titanbay works with (wealth managers, fund managers,
-- family offices). Grain: one row per partner.
with source as (
    select * from {{ ref('platform_partners') }}
)

select
    partner_id,
    trim(partner_name) as partner_name,
    lower(trim(partner_type)) as partner_type
from source
