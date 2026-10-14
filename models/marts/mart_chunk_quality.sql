-- ⚠️ The chunking problem, measured.
--
-- A chunk that is too large dilutes its embedding; one that is too small loses the
-- context the answer needed. Both are visible here as distribution tails rather than
-- as a single average, because the average is fine in both cases.

select
    topic,
    count(*)                                                    as chunks,
    min(characters)                                             as min_chars,
    percentile_cont(0.5) within group (order by characters)     as median_chars,
    max(characters)                                             as max_chars,

    -- ⚠️ THE TWO TAILS, COUNTED SEPARATELY. A single "out of range" count hides which
    -- direction the problem is, and the fix is opposite in each case.
    count(*) filter (where characters < 200)                    as too_short,
    count(*) filter (where characters > 1200)                   as too_long,

    count(*) filter (where not has_embedding)                   as missing_embeddings,

    case
        when count(*) filter (where characters > 1200) > count(*) * 0.15 then 'large chunks dominate'
        when count(*) filter (where characters < 200) > count(*) * 0.15 then 'chunks are fragmented'
        when count(*) filter (where not has_embedding) > 0 then 'embedding backlog'
        else 'within range'
    end                                                         as diagnosis

from {{ ref('stg_chunks') }}
group by topic
order by missing_embeddings desc, too_long desc
