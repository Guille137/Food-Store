-- 1. Tamaño de la base actual
SELECT current_database() AS base,
       pg_size_pretty(pg_database_size(current_database())) AS tamano;

-- 2. Conexiones y transacciones
SELECT numbackends, xact_commit, xact_rollback
FROM pg_stat_database
WHERE datname = current_database();

-- 3. Estado de tablas y mantenimiento automático
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_dead_tup DESC, relname;

-- 4. Consultas activas, excluyendo esta conexión
SELECT pid, state, now() - query_start AS duracion, query
FROM pg_stat_activity
WHERE datname = current_database()
  AND state <> 'idle'
  AND pid <> pg_backend_pid()
ORDER BY query_start;