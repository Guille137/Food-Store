-- Huella de contenido: una línea por tabla con cantidad de filas y md5 de todo
-- su contenido ordenado. Dos bases con la misma huella tienen los mismos datos.
-- Se usa para probar que un ROLLBACK, una reversión o una restauración dejaron
-- la base exactamente como estaba. Solo lectura.
-- Uso: psql -X -At -d BASE -f tpi2/base/huella.sql
SELECT format(
    'SELECT %L, count(*), md5(coalesce(string_agg(t::text, chr(10) ORDER BY t::text), '''')) FROM %I.%I AS t',
    schemaname || '.' || tablename, schemaname, tablename)
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'auditoria')
ORDER BY schemaname, tablename
\gexec
