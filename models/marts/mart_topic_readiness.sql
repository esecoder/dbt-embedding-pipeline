-- ⚠️ THE MODEL THE RETRIEVAL SERVICE ACTUALLY READS.
--
-- Answers one question: which topics is this corpus ready to answer questions on?
-- A topic with approved chunks but no embeddings will abstain on every query, and
-- nothing downstream would explain why -- so the reason is computed here.

select
    s.topic,
    s.chunks,
    s.approved_chunks,
    s.approved_pct,

    count(c.doc_id) filter (where c.has_embedding)              as embedded_chunks,
    round(
        100.0 * count(c.doc_id) filter (where c.has_embedding) / nullif(s.chunks, 0), 2
    )                                                           as embedded_pct,

    round(avg(c.chars_per_token), 2)                            as avg_chars_per_token,
    max(c.characters)                                           as largest_chunk,

    -- ⚠️ A TOPIC IS ANSWERABLE ONLY IF BOTH ARE TRUE. Approved content that is not
    -- embedded is still unanswerable, and the two conditions fail independently.
    (s.approved_pct = 100 and
     count(c.doc_id) filter (where c.has_embedding) = s.chunks)  as is_answerable,

    case
        when s.approved_pct < 100 and count(c.doc_id) filter (where c.has_embedding) < s.chunks
            then 'blocked: content not approved and not embedded'
        when s.approved_pct < 100 then 'blocked: content not approved'
        when count(c.doc_id) filter (where c.has_embedding) < s.chunks then 'blocked: chunks not embedded'
        else 'ready'
    end                                                         as readiness_reason

from {{ ref('stg_sources') }} s
join {{ ref('stg_chunks') }} c on c.topic = s.topic
group by s.topic, s.chunks, s.approved_chunks, s.approved_pct
