-- Investors registered on the platform. Each investor belongs to one entity.
-- relationship_manager_id is null (~41%) when the investor self-manages.
-- Grain: one row per investor.
with source as (
    select * from {{ ref('platform_investors') }}
)

select
    investor_id,
    user_id,
    -- Normalised email is the primary key for resolving ticket requesters back
    -- to a known investor.
    lower(trim(email))                  as email,
    trim(full_name)                     as full_name,
    entity_id,
    trim(country)                       as country,
    cast(created_at as timestamp)       as created_at,
    relationship_manager_id
from source
