-- Read-only diagnostics. Run after at least 7 representative production days.
-- Do NOT reset pg_stat_user_indexes just before collecting the observation window.

SELECT
  indexrelid::regclass AS index_name,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
  pg_get_indexdef(indexrelid) AS definition
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND relname = 'results'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Also inspect the query workload and plans before dropping an index.
-- Replace the predicate with real dashboard/feed queries and run EXPLAIN (ANALYZE, BUFFERS)
-- on a staging copy or during an approved low-traffic window.
SELECT
  index_class.relname AS index_name,
  index_state.indisvalid AS is_valid,
  index_state.indisready AS is_ready,
  pg_get_indexdef(index_state.indexrelid) AS definition
FROM pg_catalog.pg_index AS index_state
JOIN pg_catalog.pg_class AS index_class ON index_class.oid = index_state.indexrelid
JOIN pg_catalog.pg_class AS table_class ON table_class.oid = index_state.indrelid
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = table_class.relnamespace
WHERE namespace.nspname = 'public'
  AND table_class.relname = 'results'
ORDER BY index_class.relname;
