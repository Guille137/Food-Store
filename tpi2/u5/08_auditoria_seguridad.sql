-- Unidad 5 · Paso 8: auditoría de seguridad del esquema de permisos.
-- Consultas de control propuestas por el asistente de IA al revisar 04_roles.sql.
-- Cada una busca una clase de defecto conocida; "0 filas" significa "sin
-- hallazgos de esa clase". La lectura de los resultados y la decisión sobre cada
-- hallazgo están en tpi2/u5/auditoria_permisos_ia.md.
-- Solo lectura. Ejecutar como superusuario.

\echo 'A1. Privilegios otorgados a PUBLIC en objetos del proyecto (esperado: 0 filas)'
WITH esquemas(n) AS (VALUES ('public'),('unidad4'),('legado'),('migracion'),('auditoria'),('seguridad'),('anon'),('sync'))
SELECT 'tabla' AS clase, n.nspname || '.' || c.relname AS objeto, a.privilege_type
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(c.relacl) a
WHERE n.nspname IN (SELECT n FROM esquemas) AND a.grantee = 0
UNION ALL
SELECT 'rutina', n.nspname || '.' || p.proname, 'EXECUTE'
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN (SELECT n FROM esquemas)
  AND has_function_privilege('public', p.oid, 'EXECUTE')
UNION ALL
SELECT 'esquema', n.nspname, a.privilege_type
FROM pg_namespace n, aclexplode(n.nspacl) a
WHERE n.nspname IN (SELECT n FROM esquemas) AND a.grantee = 0
UNION ALL
SELECT 'base', d.datname, a.privilege_type
FROM pg_database d, aclexplode(d.datacl) a
WHERE d.datname = current_database() AND a.grantee = 0
ORDER BY 1, 2;

\echo 'A2. Funciones SECURITY DEFINER sin search_path fijo o con dueño superusuario (esperado: 0 filas)'
SELECT n.nspname || '.' || p.proname AS rutina, o.rolname AS dueno, o.rolsuper AS dueno_es_superusuario,
       p.proconfig AS configuracion
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_roles o ON o.oid = p.proowner
WHERE p.prosecdef
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND (o.rolsuper OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) AS c WHERE c LIKE 'search_path=%'));

\echo 'A2b. Inventario de funciones SECURITY DEFINER (informativo)'
SELECT n.nspname || '.' || p.proname AS rutina, o.rolname AS dueno,
       (SELECT c FROM unnest(p.proconfig) AS c WHERE c LIKE 'search_path=%') AS search_path
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_roles o ON o.oid = p.proowner
WHERE p.prosecdef AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY 1;

\echo 'A3. Roles con atributos peligrosos, además del superusuario inicial (esperado: 0 filas)'
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls
FROM pg_roles
WHERE rolname NOT LIKE 'pg\_%' AND oid <> 10
  AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls);

\echo 'A4. Membresías con ADMIN OPTION: permitirían re-otorgar el rol (esperado: 0 filas)'
SELECT m.rolname AS miembro, g.rolname AS rol, am.admin_option
FROM pg_auth_members am JOIN pg_roles m ON m.oid = am.member JOIN pg_roles g ON g.oid = am.roleid
WHERE am.admin_option AND m.oid <> 10 AND g.rolname NOT LIKE 'pg\_%';

\echo 'A5. Privilegios con GRANT OPTION (esperado: 0 filas)'
SELECT grantee, table_schema || '.' || table_name AS objeto, privilege_type
FROM information_schema.table_privileges
WHERE is_grantable = 'YES' AND grantee NOT IN ('postgres', 'fs_owner')
  AND table_schema NOT IN ('pg_catalog', 'information_schema');

\echo 'A6. ¿Algún rol que no sea admin puede leer el hash de las contraseñas? (esperado: 0 filas)'
SELECT r.rolname
FROM pg_roles r
WHERE r.rolname NOT LIKE 'pg\_%' AND r.rolname NOT IN ('postgres', 'fs_owner')
  AND has_column_privilege(r.oid, 'public.usuario', 'password_hash', 'SELECT')
  AND r.rolname NOT IN ('rol_respaldo', 'operador_respaldo');

\echo 'A6b. Roles que SÍ leen el hash por diseño (respaldo completo de la base)'
SELECT r.rolname
FROM pg_roles r
WHERE r.rolname NOT LIKE 'pg\_%' AND r.rolname NOT IN ('postgres', 'fs_owner')
  AND has_column_privilege(r.oid, 'public.usuario', 'password_hash', 'SELECT');

\echo 'A7. Roles con DELETE o TRUNCATE sobre tablas del negocio (esperado: 0 filas)'
SELECT r.rolname, c.relname,
       has_table_privilege(r.oid, c.oid, 'DELETE') AS puede_delete,
       has_table_privilege(r.oid, c.oid, 'TRUNCATE') AS puede_truncate
FROM pg_roles r CROSS JOIN pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND r.rolname NOT LIKE 'pg\_%' AND r.rolname NOT IN ('postgres', 'fs_owner')
  AND (has_table_privilege(r.oid, c.oid, 'DELETE') OR has_table_privilege(r.oid, c.oid, 'TRUNCATE'));

\echo 'A8. Roles que pueden escribir en la auditoría (esperado: 0 filas)'
SELECT r.rolname, c.relname
FROM pg_roles r CROSS JOIN pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'auditoria' AND c.relkind = 'r'
  AND r.rolname NOT LIKE 'pg\_%' AND r.rolname NOT IN ('postgres', 'fs_owner')
  AND has_table_privilege(r.oid, c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE');

\echo 'A9. Roles de login sin límite de conexiones o sin contraseña SCRAM (esperado: 0 filas)'
SELECT a.rolname, a.rolconnlimit, left(a.rolpassword, 14) AS tipo_de_clave
FROM pg_authid a
WHERE a.rolcanlogin AND a.oid <> 10 AND a.rolname NOT LIKE 'pg\_%'
  AND (a.rolconnlimit < 0 OR a.rolpassword IS NULL OR a.rolpassword NOT LIKE 'SCRAM-SHA-256$%');

\echo 'A10. Tablas del negocio a las que ningún rol de aplicación accede (informativo)'
SELECT n.nspname || '.' || c.relname AS tabla
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND NOT EXISTS (SELECT 1 FROM pg_roles r WHERE r.rolname LIKE 'rol\_%' AND r.rolname <> 'rol_respaldo'
                  AND has_table_privilege(r.oid, c.oid, 'SELECT'))
  AND NOT EXISTS (SELECT 1 FROM pg_attribute a, pg_roles r
                  WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
                    AND r.rolname LIKE 'rol\_%' AND r.rolname <> 'rol_respaldo'
                    AND has_column_privilege(r.oid, c.oid, a.attnum, 'SELECT'))
ORDER BY 1;

\echo 'A11. Privilegios por defecto para objetos futuros'
SELECT pg_get_userbyid(d.defaclrole) AS creador, COALESCE(n.nspname, '(todos los esquemas)') AS esquema,
       CASE d.defaclobjtype WHEN 'r' THEN 'tablas' WHEN 'f' THEN 'rutinas' WHEN 'S' THEN 'secuencias' END AS clase,
       d.defaclacl::text AS acl
FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
ORDER BY 1, 2, 3;
