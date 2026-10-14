-- The approval state of a topic, as a dimension.
--
-- ⚠️ A SEPARATE MODEL rather than a CASE inside each mart. The approved/draft rule is
-- a business definition, and it should have exactly one home.

select
    topic,
    count(*)                                                   as chunks,
    count(*) filter (where source_quality = 'approved')         as approved_chunks,
    -- ⚠️ Rounding happens HERE so no downstream model can disagree about the value.
    round(
        100.0 * count(*) filter (where source_quality = 'approved') / nullif(count(*), 0),
        2
    )                                                          as approved_pct
from {{ ref('stg_chunks') }}
group by topic
