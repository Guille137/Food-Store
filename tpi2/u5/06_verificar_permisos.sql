-- Unidad 5 · Paso 6: los permisos reales coinciden con la matriz de la spec,
-- "ni más, ni menos". Compara lo ESPERADO (design.md, transcripto abajo) con lo
-- OBTENIDO del catálogo, en los dos sentidos. Cualquier diferencia aborta.
-- Solo lectura. Ejecutar como superusuario.
\set ON_ERROR_STOP on

CREATE TEMP TABLE esperado (rol text, clase text, objeto text, privilegio text, columna text);

-- Base y esquemas
INSERT INTO esperado
SELECT r, 'BASE', current_database(), 'CONNECT', NULL
FROM unnest(ARRAY['rol_app_lectura','rol_soporte','rol_reportes','rol_auditor','rol_respaldo','rol_sync_movil']) AS r;
INSERT INTO esperado VALUES
    ('rol_app_lectura', 'ESQUEMA', 'public', 'USAGE', NULL),
    ('rol_soporte',     'ESQUEMA', 'public', 'USAGE', NULL),
    ('rol_reportes',    'ESQUEMA', 'public', 'USAGE', NULL),
    ('rol_reportes',    'ESQUEMA', 'unidad4', 'USAGE', NULL),
    ('rol_reportes',    'ESQUEMA', 'anon', 'USAGE', NULL),
    ('rol_auditor',     'ESQUEMA', 'auditoria', 'USAGE', NULL);

-- Tablas y vistas completas
INSERT INTO esperado
SELECT rol, 'TABLA', objeto, privilegio, NULL
FROM (VALUES
    ('rol_app_lectura',   ARRAY['public.categoria','public.producto','public.tp5_productos_vigentes'], 'SELECT'),
    ('rol_app_escritura', ARRAY['public.cliente','public.pedido','public.detalle_pedido'], 'SELECT'),
    ('rol_app_escritura', ARRAY['public.cliente'], 'INSERT'),
    ('rol_soporte',       ARRAY['public.categoria','public.producto','public.cliente','public.pedido',
                                'public.detalle_pedido','public.entrega','public.repartidor',
                                'public.zona'], 'SELECT'),
    ('rol_reportes',      ARRAY['public.tp5_productos_vigentes',
                                'public.tp5_detalles_productos','public.tp5_facturacion_mensual',
                                'unidad4.ventas_categoria_diaria','unidad4.top_categorias_materializado',
                                'anon.usuario_anon','anon.cliente_anon','anon.pedido_anon'], 'SELECT'),
    ('rol_auditor',       ARRAY['auditoria.registro','auditoria.intento_login',
                                'auditoria.v_alerta_fuerza_bruta','auditoria.v_actividad_por_rol'], 'SELECT'),
    ('rol_admin_datos',   ARRAY['public.categoria','public.producto'], 'INSERT')
) AS m(rol, objetos, privilegio), unnest(m.objetos) AS objeto;

-- Privilegios por columna
INSERT INTO esperado
SELECT rol, 'COLUMNA', objeto, privilegio, columna
FROM (VALUES
    ('rol_app_escritura', 'public.cliente', 'UPDATE', ARRAY['nombre','apellido','nro_telefono']),
    ('rol_app_escritura', 'public.pedido',  'UPDATE', ARRAY['estado']),
    ('rol_soporte', 'public.usuario', 'SELECT', ARRAY['id_usuario','correo_electronico','nombre','apellido',
                                                      'rol_aplicacion','activo','fecha_alta','bloqueado_hasta']),
    ('rol_soporte', 'public.cliente', 'UPDATE', ARRAY['nro_telefono']),
    ('rol_soporte', 'public.pedido',  'UPDATE', ARRAY['estado']),
    ('rol_admin_datos', 'public.categoria', 'UPDATE', ARRAY['nombre','activo']),
    ('rol_admin_datos', 'public.producto',  'UPDATE', ARRAY['nombre','precio_lista','stock','activo','categoria_id']),
    ('rol_admin_datos', 'public.usuario',   'UPDATE', ARRAY['nombre','apellido','rol_aplicacion','activo'])
) AS m(rol, objeto, privilegio, columnas), unnest(m.columnas) AS columna;

-- Funciones y procedimientos
INSERT INTO esperado VALUES
    ('rol_app_escritura', 'RUTINA', 'public.tpi_registrar_pedido', 'EXECUTE', NULL),
    ('rol_app_escritura', 'RUTINA', 'public.tpi_total_pedido', 'EXECUTE', NULL),
    ('rol_app_escritura', 'RUTINA', 'public.fn_autenticar', 'EXECUTE', NULL),
    ('rol_soporte',       'RUTINA', 'public.tpi_total_pedido', 'EXECUTE', NULL),
    ('rol_admin_datos',   'RUTINA', 'public.tpi_baja_producto', 'EXECUTE', NULL),
    ('rol_admin_datos',   'RUTINA', 'public.fn_resetear_password', 'EXECUTE', NULL);

-- Sincronización móvil (Unidad 8)
INSERT INTO esperado VALUES
    ('rol_sync_movil', 'ESQUEMA', 'sync', 'USAGE', NULL),
    ('rol_sync_movil', 'TABLA',   'sync.v_snapshot_movil', 'SELECT', NULL),
    ('rol_sync_movil', 'RUTINA',  'sync.aplicar_solicitud', 'EXECUTE', NULL);

-- Lo que el catálogo dice. Se excluyen los dueños (fs_owner y el superusuario).
CREATE TEMP VIEW obtenido AS
WITH esquemas(nombre) AS (
    SELECT nspname FROM pg_namespace
    WHERE nspname IN ('public','unidad4','legado','migracion','auditoria','seguridad','anon','sync')
), rol(oid, nombre) AS (
    SELECT oid, rolname FROM pg_roles UNION ALL SELECT 0, 'PUBLIC'
)
SELECT r.nombre AS rol, 'BASE' AS clase, d.datname::text AS objeto, a.privilege_type AS privilegio, NULL::text AS columna
FROM pg_database d, aclexplode(d.datacl) a JOIN rol r ON r.oid = a.grantee
WHERE d.datname = current_database() AND a.grantee <> d.datdba
UNION ALL
SELECT r.nombre, 'ESQUEMA', n.nspname, a.privilege_type, NULL
FROM pg_namespace n, aclexplode(n.nspacl) a JOIN rol r ON r.oid = a.grantee
WHERE n.nspname IN (SELECT nombre FROM esquemas) AND a.grantee <> n.nspowner
UNION ALL
SELECT r.nombre, 'TABLA', n.nspname || '.' || c.relname, a.privilege_type, NULL
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
     aclexplode(c.relacl) a JOIN rol r ON r.oid = a.grantee
WHERE n.nspname IN (SELECT nombre FROM esquemas) AND c.relkind IN ('r','v','m','S')
  AND a.grantee <> c.relowner
UNION ALL
SELECT r.nombre, 'COLUMNA', n.nspname || '.' || c.relname, a.privilege_type, at.attname
FROM pg_attribute at JOIN pg_class c ON c.oid = at.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace,
     aclexplode(at.attacl) a JOIN rol r ON r.oid = a.grantee
WHERE n.nspname IN (SELECT nombre FROM esquemas) AND NOT at.attisdropped
UNION ALL
SELECT r.nombre, 'RUTINA', n.nspname || '.' || p.proname, a.privilege_type, NULL
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
     aclexplode(p.proacl) a JOIN rol r ON r.oid = a.grantee
WHERE n.nspname IN (SELECT nombre FROM esquemas) AND a.grantee <> p.proowner;

CREATE TEMP VIEW diferencia AS
(SELECT 'FALTA (previsto y no otorgado)' AS problema, * FROM
    (SELECT * FROM esperado EXCEPT SELECT * FROM obtenido WHERE rol NOT IN ('fs_owner','pg_database_owner')) AS f)
UNION ALL
(SELECT 'SOBRA (otorgado y no previsto)', * FROM
    (SELECT * FROM obtenido WHERE rol NOT IN ('fs_owner','pg_database_owner') EXCEPT SELECT * FROM esperado) AS s);

\echo '=== Roles (equivalente a \\du) ==='
SELECT r.rolname AS rol,
       concat_ws(', ', CASE WHEN r.rolcanlogin THEN 'LOGIN' ELSE 'sin login' END,
                 CASE WHEN r.rolsuper THEN 'SUPERUSUARIO' END,
                 CASE WHEN r.rolcreaterole THEN 'CREATEROLE' END,
                 CASE WHEN r.rolcreatedb THEN 'CREATEDB' END,
                 CASE WHEN r.rolbypassrls THEN 'BYPASSRLS' END) AS atributos,
       COALESCE((SELECT string_agg(g.rolname, ', ' ORDER BY g.rolname)
                 FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid
                 WHERE m.member = r.oid), '-') AS miembro_de
FROM pg_roles r
WHERE r.rolname NOT LIKE 'pg\_%'
ORDER BY r.rolcanlogin, r.rolname;

\echo '=== Privilegios de tabla (information_schema.role_table_grants) ==='
SELECT grantee AS rol, table_schema || '.' || table_name AS objeto,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
FROM information_schema.role_table_grants
WHERE grantee LIKE 'rol\_%'
GROUP BY 1, 2 ORDER BY 1, 2;

\echo '=== Privilegios por columna ==='
SELECT rol, objeto, privilegio, string_agg(columna, ', ' ORDER BY columna) AS columnas
FROM obtenido WHERE clase = 'COLUMNA' GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

\echo '=== Rutinas ejecutables por rol ==='
SELECT rol, string_agg(objeto, ', ' ORDER BY objeto) AS rutinas
FROM obtenido WHERE clase = 'RUTINA' AND rol <> 'fs_owner' GROUP BY 1 ORDER BY 1;

\echo '=== Diferencias entre la spec y el catálogo (debe devolver 0 filas) ==='
SELECT * FROM diferencia ORDER BY 1, 2, 3, 4, 5, 6;

DO $$
DECLARE v_esperado bigint; v_dif bigint;
BEGIN
    SELECT count(*) INTO v_esperado FROM esperado;
    SELECT count(*) INTO v_dif FROM diferencia;
    IF v_dif > 0 THEN
        RAISE EXCEPTION 'Los permisos no coinciden con la spec: % diferencias', v_dif;
    END IF;
    RAISE NOTICE 'PERMISOS VERIFICADOS: % privilegios previstos, 0 faltantes, 0 sobrantes', v_esperado;
END $$;
