-- ⚠️ Staging does the boring work once: cast, rename, and drop what nothing needs.
-- No joins, no business logic, no aggregations. Every mart reads this, so anything
-- wrong here is wrong everywhere -- which is why it is the smallest model here.

with source as (
    select * from {{ ref('raw_chunks') }}
),

cleaned as (
    select
        doc_id,
        topic,
        chunk_index,
        characters,
        tokens,
        has_embedding,
        source_quality,

        -- ⚠️ A chunk with no characters cannot be embedded. Flagging it here rather
        -- than filtering it means the marts can COUNT the loss instead of hiding it.
        characters > 0                        as is_usable,

        -- ⚠️ Derived once, in one place. Two marts computing this differently is the
        -- classic data-quality failure, and it is invisible until the numbers diverge.
        round(characters::numeric / nullif(tokens, 0), 2) as chars_per_token

    from source
)

select * from cleaned
