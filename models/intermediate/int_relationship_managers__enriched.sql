-- RMs flattened with their owning partner. Grain: one row per RM.
with rms as (
    select * from {{ ref('stg_platform__relationship_managers') }}
),

partners as (
    select * from {{ ref('stg_platform__partners') }}
)

select
    rms.rm_id,
    rms.rm_name,
    rms.rm_email,
    rms.partner_id,
    partners.partner_name,
    partners.partner_type
from rms
left join partners on rms.partner_id = partners.partner_id
