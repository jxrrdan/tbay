-- Asserts that no email address appears in both dim_investor and
-- dim_relationship_manager. The entity resolution layer classifies
-- investor-first when an email matches both, but that precedence rule
-- only protects the data if this overlap never occurs. Any rows
-- returned here mean the assumption has been violated and the
-- investor_matched_both flag in fct_tickets should be investigated.
select i.email
from {{ ref('dim_investor') }} i
inner join {{ ref('dim_relationship_manager') }} r
    on lower(trim(i.email)) = lower(trim(r.rm_email))
