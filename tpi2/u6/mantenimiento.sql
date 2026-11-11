-- Unidad 6 · Tareas rutinarias de mantenimiento (semanal).
-- No usa VACUUM FULL (bloquea las tablas y no hace falta de rutina). VACUUM y
-- REFRESH no admiten transacción externa: se ejecuta suelto, como superusuario.
-- El autovacuum sigue activo; esto es el control y el refuerzo, no su reemplazo.
\set ON_ERROR_STOP on

\echo 'M1. Estado ANTES: filas vivas/muertas y último mantenimiento'
SELECT schemaname || '.' || relname AS tabla, n_live_tup AS vivas, n_dead_tup AS muertas,
       CASE WHEN n_live_tup + n_dead_tup > 0
            THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 1) ELSE 0 END AS pct_muertas,
       COALESCE(to_char(GREATEST(last_vacuum, last_autovacuum), 'YYYY-MM-DD HH24:MI'), 'nunca') AS ultimo_vacuum,
       COALESCE(to_char(GREATEST(last_analyze, last_autoanalyze), 'YYYY-MM-DD HH24:MI'), 'nunca') AS ultimo_analyze
FROM pg_stat_user_tables
WHERE schemaname IN ('public', 'auditoria', 'sync', 'unidad4')
ORDER BY n_dead_tup DESC, 1 LIMIT 12;

\echo 'M2. Limpieza de filas muertas y estadísticas del planificador'
VACUUM (ANALYZE);

\echo 'M3. Copias derivadas: materializadas de reportes y copias anónimas'
REFRESH MATERIALIZED VIEW CONCURRENTLY public.tp5_facturacion_mensual;
REFRESH MATERIALIZED VIEW CONCURRENTLY anon.usuario_anon;
REFRESH MATERIALIZED VIEW CONCURRENTLY anon.cliente_anon;
REFRESH MATERIALIZED VIEW CONCURRENTLY anon.pedido_anon;
ANALYZE public.tp5_facturacion_mensual, anon.usuario_anon, anon.cliente_anon, anon.pedido_anon;

\echo 'M4. Estado DESPUÉS'
SELECT schemaname || '.' || relname AS tabla, n_live_tup AS vivas, n_dead_tup AS muertas,
       to_char(last_vacuum, 'YYYY-MM-DD HH24:MI:SS') AS vacuum_manual,
       to_char(last_analyze, 'YYYY-MM-DD HH24:MI:SS') AS analyze_manual
FROM pg_stat_user_tables
WHERE schemaname IN ('public', 'auditoria', 'sync', 'unidad4')
ORDER BY 1;

\echo 'M5. Tamaños (para seguir el crecimiento semana a semana)'
SELECT pg_size_pretty(pg_database_size(current_database())) AS base,
       (SELECT pg_size_pretty(sum(pg_total_relation_size(c.oid)))
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'auditoria' AND c.relkind = 'r') AS auditoria,
       (SELECT pg_size_pretty(sum(pg_relation_size(indexrelid))) FROM pg_stat_user_indexes) AS indices;

\echo 'M6. Índices sin uso desde el último reinicio de estadísticas (candidatos a revisar, NO a borrar automáticamente)'
SELECT s.schemaname || '.' || s.indexrelname AS indice, s.relname AS tabla,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS tamano
FROM pg_stat_user_indexes s JOIN pg_index i ON i.indexrelid = s.indexrelid
WHERE s.idx_scan = 0 AND NOT i.indisunique AND NOT i.indisprimary
  AND s.schemaname IN ('public', 'auditoria', 'sync')
ORDER BY pg_relation_size(s.indexrelid) DESC LIMIT 10;

\echo 'M7. Salud: conexiones, transacciones largas y bloqueos en espera'
SELECT (SELECT count(*) FROM pg_stat_activity WHERE datname = current_database()) AS conexiones,
       (SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND xact_start < now() - INTERVAL '5 minutes') AS transacciones_mas_de_5_min,
       (SELECT count(*) FROM pg_locks WHERE NOT granted) AS bloqueos_en_espera,
       (SELECT xact_rollback FROM pg_stat_database WHERE datname = current_database()) AS rollbacks_acumulados,
       (SELECT deadlocks FROM pg_stat_database WHERE datname = current_database()) AS interbloqueos_acumulados;
