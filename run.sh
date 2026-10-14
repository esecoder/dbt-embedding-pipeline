#!/usr/bin/env bash
# dbt-embedding-pipeline — one entry point.
#
#   ./run.sh build     deps + seed + models + all 20 tests
#   ./run.sh test      the data tests alone
#   ./run.sh docs      generate and serve the lineage graph
#   ./run.sh query     show what the marts actually say
set -euo pipefail
cd "$(dirname "$0")"
export DBT_PROFILES_DIR=.
DBT="${DBT:-dbt}"

case "${1:-build}" in
  build) "$DBT" deps && "$DBT" build ;;
  test)  "$DBT" test ;;
  docs)  "$DBT" docs generate && "$DBT" docs serve ;;
  query)
    PGPASSWORD="${DBT_PASSWORD:-test}" psql -h "${DBT_HOST:-localhost}" -p "${DBT_PORT:-5433}" \
      -U "${DBT_USER:-postgres}" -d "${DBT_DBNAME:-vectors}" -c \
      "select topic, chunks, approved_pct, embedded_pct, is_answerable, readiness_reason
         from retrieval.mart_topic_readiness order by topic;"
    ;;
  *) sed -n '2,7p' "$0" ;;
esac
