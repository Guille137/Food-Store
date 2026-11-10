-- Revisión previa: tuplas muertas y fechas de mantenimiento
SELECT relname, n_live_tup, n_dead_tup,
       last_vacuum, last_autovacuum,
       last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY relname;

-- Acción justificada: actualizar estadísticas de las tablas del laboratorio.
-- La revisión previa mostró estimaciones de filas en cero y sin autoanalyze.
ANALYZE VERBOSE public.categoria;
ANALYZE VERBOSE public.cliente;
ANALYZE VERBOSE public.producto;
ANALYZE VERBOSE public.pedido;
ANALYZE VERBOSE public.detalle_pedido;

-- Comprobación posterior
SELECT relname, n_live_tup, n_dead_tup,
       last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY relname;