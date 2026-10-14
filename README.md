# dbt-embedding-pipeline

**The data layer behind a retrieval corpus: ingestion → staging → marts, with the assumptions declared and checked.**

```bash
docker run -d --name dbt-pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=vectors \
  -p 5433:5432 pgvector/pgvector:pg16
pip install "dbt-core==1.9.1" "dbt-postgres==1.9.1"

export DBT_PROFILES_DIR=.
dbt deps && dbt build && dbt docs generate
```

```
Done. PASS=25 WARN=0 ERROR=0 SKIP=0 TOTAL=25
```

---

## ⚠️ The tests are the deliverable, not the SQL

The models below are ordinary `SELECT` statements and anyone can write them. ⚠️ **What dbt adds is that the assumptions are *declared* and *checked on every run*** — so a pipeline that starts producing duplicates, nulls or an unapproved topic **stops the build** instead of quietly feeding the retrieval service wrong data.

**20 data tests** across four models, and the ones that matter are not the `not_null`s:

| Test | Why it is there |
|---|---|
| `accepted_values` on `topic` | ⚠️ A **new** topic arriving from the source is a schema change, and a mart that silently gains a row is how a dashboard changes meaning overnight |
| `unique` on `doc_id` | A duplicated chunk is retrieved twice, inflating its apparent relevance — **and nothing downstream would show it** |
| `dbt_utils.accepted_range` on `characters` (`min 1`) | ⚠️ **Zero-length chunks are the failure that reaches production**, because they are not null and they embed to noise |
| `accepted_range` on `approved_pct` (`0–100`) | A percentage outside the range means the denominator is wrong — **and a wrong percentage looks exactly like a normal percentage** |
| `accepted_values` on `readiness_reason` | ⚠️ Bounds the vocabulary. A free-text reason field drifts into four spellings of the same explanation and stops being groupable |
| `unique` on `mart_topic_readiness.topic` | The mart is joined by the service; a duplicate key doubles every upstream metric |

---

## What it measures

**`mart_topic_readiness`** — can this corpus answer questions on a topic?

```
 topic      | chunks | approved_pct | embedded_pct | is_answerable | readiness_reason
 agents     |    403 |        61.54 |        92.31 | f             | blocked: content not approved and not embedded
 chunking   |    388 |        61.86 |        92.27 | f             | blocked: content not approved and not embedded
 evaluation |    416 |        58.89 |        92.31 | f             | blocked: content not approved and not embedded
 retrieval  |    395 |        61.77 |        91.14 | f             | blocked: content not approved and not embedded
 serving    |    424 |        61.79 |        93.16 | f             | blocked: content not approved and not embedded
 vectors    |    374 |        64.44 |        91.98 | f             | blocked: content not approved and not embedded
```

⚠️ **What this shows is the value of the model, not a bug in the data.** The seed deliberately contains unreviewed and draft content plus an embedding backlog, and **no topic is answerable — for two independent reasons at once.** A pipeline that reported "94% embedded, looking good" would be describing a corpus that **abstains on every question while appearing healthy.**

⚠️ **The two conditions fail independently, and that is why `is_answerable` is an `AND`.** Approved content that is not embedded is still unanswerable; embedded content that is not approved is still not usable. Reporting either alone would be a number that never changes when the problem does.

**`mart_chunk_quality`** — the chunking problem, measured:

```
 topic      | min | median | max  | too_short | too_long | diagnosis
 agents     | 124 |    799 | 1395 |        17 |       67 | large chunks dominate
 chunking   | 121 |    780 | 1400 |        30 |       66 | large chunks dominate
 evaluation | 122 |  739.5 | 1400 |        31 |       64 | large chunks dominate
 serving    | 124 |  765.5 | 1397 |        28 |       62 | embedding backlog
```

⚠️ **The median is healthy in every topic — 740 to 820 characters — and that is exactly the point.** A pipeline reporting the average would say the chunking is fine. **The tails are where retrieval breaks:** ~65 chunks over 1,200 characters dilute their embedding, and ~28 under 200 lose the context the answer needed. **The fix is opposite in each direction, which is why the two counts are separate columns and not one "out of range" figure.**

---

## The three design decisions

**1. Materialisation is chosen per layer, not defaulted.** `staging` = **view** (cheap, always current, only read through the marts); `marts` = **table** (read by the retrieval service on every query, so worth materialising). ⚠️ Materialising staging as tables doubles warehouse cost for no gain; rebuilding every mart on every run is how a pipeline gets slow without anyone deciding it should.

**2. `chars_per_token` is computed once, in staging.** ⚠️ Two marts deriving the same metric differently is the classic data-quality failure and it is **invisible until the numbers diverge** — at which point nobody knows which one is right.

**3. The approval rule lives in exactly one model.** `stg_sources` owns "what counts as approved". A `CASE` repeated across marts is a business definition with four copies and no owner.

---

## ⚠️ On Snowflake

**This runs on PostgreSQL.** Snowflake's trial needed an account I could not create, so rather than claim it I built the same pipeline somewhere real and kept the SQL **portable**: no Postgres-only functions, no window-function extensions, standard `filter (where ...)` aggregates.

**What would actually differ on Snowflake is the part worth knowing** — and it is not the SQL:

| | PostgreSQL here | Snowflake |
|---|---|---|
| Ingestion | `dbt seed` from CSV | **stages** + `COPY INTO`, and file-format handling |
| Compute | the local machine | **virtual warehouse** — sizing and auto-suspend decide the cost |
| Materialisation | view / table | + **transient** and **dynamic tables** |
| Cost model | free | ⚠️ **per-second compute**, so a rebuild-on-every-run pipeline is a bill |

⚠️ **The last row is the one that changes engineering behaviour.** On Postgres a full rebuild is free and the materialisation choice is about tidiness; on Snowflake it is about money, and `+materialized: view` stops being a style preference.

---

## Test coverage

`dbt build` runs the seed, both layers of models and **all 20 data tests** in dependency order, and fails the whole run on any failure. `dbt docs generate` produces the lineage graph.
