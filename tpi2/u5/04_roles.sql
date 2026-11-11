-- Unidad 5 · Paso 4: roles y permisos con mínimo privilegio.
-- Spec: .kiro/specs/u5-roles-permisos/ (requirements y design). Cada GRANT de
-- este archivo responde a una fila de la matriz de design.md; lo que no figura
-- allí no se otorga.
--
-- Ejecutar como superusuario, dentro de una transacción externa, pasando las
-- contraseñas de laboratorio como variables de psql (nunca escritas en el repo):
--   psql -v clave_app_web=... -v clave_admin_datos=... -v clave_soporte=...
--        -v clave_analista=... -v clave_auditor=... -v clave_respaldo=... -v clave_tablet=...
-- Orden: después de tpi2/u5/01-03 y de tpi2/u8/servidor_sync.sql (esquema sync).
-- Los roles son del servidor (no de la base): se crean solo si faltan.

-- ---------------------------------------------------------------------------
-- 1. Roles
-- ---------------------------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
    -- Dueño de los objetos: sin login y sin atributos especiales. Las funciones
    -- SECURITY DEFINER se ejecutan con SUS privilegios, no con los de un superusuario.
    FOREACH r IN ARRAY ARRAY['fs_owner', 'rol_app_lectura', 'rol_app_escritura', 'rol_soporte',
                             'rol_reportes', 'rol_auditor', 'rol_respaldo', 'rol_admin_datos',
                             'rol_sync_movil'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', r);
        END IF;
    END LOOP;
    FOREACH r IN ARRAY ARRAY['app_web', 'admin_datos', 'soporte_01', 'analista_01',
                             'auditor_01', 'operador_respaldo', 'tablet_feria'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT', r);
        END IF;
    END LOOP;
END $$;

-- Los roles de login heredan de su grupo, y de nadie más.
ALTER ROLE app_web INHERIT CONNECTION LIMIT 20;
ALTER ROLE admin_datos INHERIT CONNECTION LIMIT 3;
ALTER ROLE soporte_01 INHERIT CONNECTION LIMIT 3;
ALTER ROLE analista_01 INHERIT CONNECTION LIMIT 3;
ALTER ROLE auditor_01 INHERIT CONNECTION LIMIT 3;
ALTER ROLE operador_respaldo INHERIT CONNECTION LIMIT 2;
ALTER ROLE tablet_feria INHERIT CONNECTION LIMIT 5;

-- Las contraseñas no deben quedar en el log de auditoría (log_statement las
-- registraría en claro dentro del ALTER ROLE): se silencia solo este tramo.
SET LOCAL log_statement = 'none';
SET LOCAL log_min_error_statement = 'panic';
ALTER ROLE app_web           PASSWORD :'clave_app_web';
ALTER ROLE admin_datos       PASSWORD :'clave_admin_datos';
ALTER ROLE soporte_01        PASSWORD :'clave_soporte';
ALTER ROLE analista_01       PASSWORD :'clave_analista';
ALTER ROLE auditor_01        PASSWORD :'clave_auditor';
ALTER ROLE operador_respaldo PASSWORD :'clave_respaldo';
ALTER ROLE tablet_feria      PASSWORD :'clave_tablet';
RESET log_min_error_statement;
RESET log_statement;

GRANT rol_app_lectura   TO rol_app_escritura;
GRANT rol_app_escritura TO app_web;
GRANT rol_app_escritura, rol_soporte TO rol_admin_datos;
GRANT rol_admin_datos   TO admin_datos;
GRANT rol_soporte       TO soporte_01;
GRANT rol_reportes      TO analista_01;
GRANT rol_auditor       TO auditor_01;
GRANT rol_respaldo      TO operador_respaldo;
GRANT rol_sync_movil    TO tablet_feria;
-- pg_dump necesita leer todo; rol predefinido de solo lectura, sin escritura.
GRANT pg_read_all_data  TO rol_respaldo;

-- Las personas (no la aplicación) quedan con TODAS sus sentencias en el log,
-- incluidas las lecturas. La aplicación no: pasaría contraseñas por fn_autenticar.
ALTER ROLE soporte_01  SET log_statement = 'all';
ALTER ROLE admin_datos SET log_statement = 'all';
ALTER ROLE analista_01 SET log_statement = 'all';

-- ---------------------------------------------------------------------------
-- 2. Propiedad de los objetos: todo pasa a fs_owner
-- ---------------------------------------------------------------------------
DO $$
DECLARE o record;
BEGIN
    FOR o IN SELECT nspname FROM pg_namespace
             WHERE nspname IN ('unidad4', 'legado', 'migracion', 'auditoria', 'seguridad', 'anon', 'sync') LOOP
        EXECUTE format('ALTER SCHEMA %I OWNER TO fs_owner', o.nspname);
    END LOOP;
    FOR o IN SELECT n.nspname, c.relname, c.relkind FROM pg_class c
             JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname IN ('public', 'unidad4', 'legado', 'migracion', 'auditoria', 'seguridad', 'anon', 'sync')
               AND c.relkind IN ('r', 'v', 'm') LOOP
        EXECUTE format('ALTER %s %I.%I OWNER TO fs_owner',
            CASE o.relkind WHEN 'r' THEN 'TABLE' WHEN 'v' THEN 'VIEW' ELSE 'MATERIALIZED VIEW' END,
            o.nspname, o.relname);
    END LOOP;
    -- Funciones propias (no las de extensiones como pgcrypto).
    FOR o IN SELECT p.oid::regprocedure AS firma, p.prokind FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname IN ('public', 'unidad4', 'auditoria', 'seguridad', 'sync')
               AND NOT EXISTS (SELECT 1 FROM pg_depend d
                               WHERE d.objid = p.oid AND d.deptype = 'e') LOOP
        EXECUTE format('ALTER %s %s OWNER TO fs_owner',
            CASE o.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END, o.firma);
    END LOOP;
    FOR o IN SELECT t.typname FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
             WHERE n.nspname = 'public' AND t.typtype = 'e' LOOP
        EXECUTE format('ALTER TYPE public.%I OWNER TO fs_owner', o.typname);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Punto de partida: nadie tiene nada
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO rol_app_lectura, rol_soporte, rol_reportes,
                    rol_auditor, rol_respaldo, rol_sync_movil', current_database());
    -- REFRESH MATERIALIZED VIEW CONCURRENTLY se ejecuta como dueño de la vista y
    -- usa tablas temporales: fs_owner necesita TEMPORARY (detectado al probar U6).
    EXECUTE format('GRANT TEMPORARY ON DATABASE %I TO fs_owner', current_database());
END $$;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public, unidad4, legado, migracion, auditoria, seguridad, anon, sync FROM PUBLIC;
-- PostgreSQL da EXECUTE a PUBLIC en toda función nueva: se quita.
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public, unidad4, auditoria, seguridad, sync FROM PUBLIC;
-- fs_owner ejecuta las funciones de pgcrypto desde fn_autenticar y seudonimo.
-- También crea los objetos futuros del esquema public (SET ROLE fs_owner).
GRANT USAGE, CREATE ON SCHEMA public TO fs_owner;
GRANT EXECUTE ON FUNCTION public.crypt(text, text), public.gen_salt(text, integer),
                          public.gen_random_bytes(integer), public.digest(text, text) TO fs_owner;

-- Las reglas de negocio (triggers) bloquean filas de producto/categoría/pedido
-- con FOR SHARE, que exige privilegio UPDATE, y la Unidad 4 refresca una
-- materializada, que exige ser su dueño. Para no darle esos privilegios a la
-- aplicación, las funciones de trigger pasan a ejecutarse como fs_owner, con
-- search_path fijo.
ALTER FUNCTION public.validar_edicion_detalle_pedido()   SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.validar_producto_y_stock_detalle() SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.tpi_validar_categorias_detalle()   SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION unidad4.sincronizar_ventas()              SECURITY DEFINER SET search_path = pg_catalog, pg_temp;
-- El alta de pedidos se hace SOLO por este procedimiento: la aplicación no
-- recibe INSERT directo sobre pedido ni detalle_pedido.
ALTER PROCEDURE public.tpi_registrar_pedido(integer, public.forma_pago, jsonb, integer)
    SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

-- ---------------------------------------------------------------------------
-- 4. Privilegios por rol (matriz de design.md)
-- ---------------------------------------------------------------------------
-- rol_app_lectura: mostrar el catálogo.
GRANT USAGE ON SCHEMA public TO rol_app_lectura;
GRANT SELECT ON public.categoria, public.producto, public.tp5_productos_vigentes TO rol_app_lectura;

-- rol_app_escritura: registrar clientes y pedidos, autenticar al personal.
GRANT SELECT, INSERT ON public.cliente TO rol_app_escritura;
GRANT UPDATE (nombre, apellido, nro_telefono) ON public.cliente TO rol_app_escritura;
GRANT SELECT ON public.pedido, public.detalle_pedido TO rol_app_escritura;
GRANT UPDATE (estado) ON public.pedido TO rol_app_escritura;
GRANT EXECUTE ON PROCEDURE public.tpi_registrar_pedido(integer, public.forma_pago, jsonb, integer) TO rol_app_escritura;
GRANT EXECUTE ON FUNCTION public.tpi_total_pedido(integer) TO rol_app_escritura;
GRANT EXECUTE ON FUNCTION public.fn_autenticar(text, text) TO rol_app_escritura;

-- rol_soporte: atender consultas de clientes; ve al personal sin el hash.
GRANT USAGE ON SCHEMA public TO rol_soporte;
GRANT SELECT ON public.categoria, public.producto, public.cliente, public.pedido,
                public.detalle_pedido TO rol_soporte;
GRANT SELECT (id_usuario, correo_electronico, nombre, apellido, rol_aplicacion, activo,
              fecha_alta, bloqueado_hasta) ON public.usuario TO rol_soporte;
-- Hallazgo A10 de la auditoría de seguridad: las tablas de reparto creadas por
-- la migración no tenían política. Soporte las consulta ("¿quién llevó mi pedido?").
GRANT SELECT ON public.entrega, public.repartidor, public.zona TO rol_soporte;
GRANT UPDATE (nro_telefono) ON public.cliente TO rol_soporte;
GRANT UPDATE (estado) ON public.pedido TO rol_soporte;
GRANT EXECUTE ON FUNCTION public.tpi_total_pedido(integer) TO rol_soporte;

-- rol_reportes: solo vistas sin datos de contacto y vistas anonimizadas.
GRANT USAGE ON SCHEMA public, unidad4, anon TO rol_reportes;
-- Hallazgo H3 de la auditoría asistida por IA: tp5_pedidos_clientes expone nombre
-- y apellido de clientes; reportes usa en su lugar anon.pedido_anon.
GRANT SELECT ON public.tp5_productos_vigentes, public.tp5_detalles_productos,
                public.tp5_facturacion_mensual TO rol_reportes;
GRANT SELECT ON unidad4.ventas_categoria_diaria, unidad4.top_categorias_materializado TO rol_reportes;
GRANT SELECT ON anon.usuario_anon, anon.cliente_anon, anon.pedido_anon TO rol_reportes;

-- rol_auditor: lee la auditoría; no puede tocar los datos del negocio.
GRANT USAGE ON SCHEMA auditoria TO rol_auditor;
GRANT SELECT ON auditoria.registro, auditoria.intento_login,
                auditoria.v_alerta_fuerza_bruta, auditoria.v_actividad_por_rol TO rol_auditor;

-- rol_admin_datos: mantiene catálogo y personal. Sin DELETE (las bajas son
-- lógicas) y sin acceso al hash: las claves se restablecen por función.
GRANT INSERT ON public.categoria, public.producto TO rol_admin_datos;
GRANT UPDATE (nombre, activo) ON public.categoria TO rol_admin_datos;
GRANT UPDATE (nombre, precio_lista, stock, activo, categoria_id) ON public.producto TO rol_admin_datos;
GRANT UPDATE (nombre, apellido, rol_aplicacion, activo) ON public.usuario TO rol_admin_datos;
GRANT EXECUTE ON PROCEDURE public.tpi_baja_producto(integer) TO rol_admin_datos;
GRANT EXECUTE ON FUNCTION public.fn_resetear_password(text) TO rol_admin_datos;

-- rol_sync_movil (tablets): lee la instantánea del catálogo y propone pedidos
-- por una única función. No ve clientes, pedidos ni usuarios.
GRANT USAGE ON SCHEMA sync TO rol_sync_movil;
GRANT SELECT ON sync.v_snapshot_movil TO rol_sync_movil;
GRANT EXECUTE ON FUNCTION sync.aplicar_solicitud(jsonb) TO rol_sync_movil;

-- ---------------------------------------------------------------------------
-- 5. Objetos futuros
-- ---------------------------------------------------------------------------
-- Toda función nueva nace SIN ejecución para PUBLIC.
ALTER DEFAULT PRIVILEGES FOR ROLE fs_owner REVOKE EXECUTE ON ROUTINES FROM PUBLIC;
-- Lo que se cree en "anon" es apto para reportes; lo que se cree en "auditoria"
-- lo lee el auditor. En "public" NO hay permiso por defecto: una tabla nueva
-- exige decidir explícitamente quién la ve.
ALTER DEFAULT PRIVILEGES FOR ROLE fs_owner IN SCHEMA anon GRANT SELECT ON TABLES TO rol_reportes;
ALTER DEFAULT PRIVILEGES FOR ROLE fs_owner IN SCHEMA auditoria GRANT SELECT ON TABLES TO rol_auditor;

SELECT rolname, rolcanlogin AS login, rolsuper AS super, rolcreaterole AS crea_roles,
       rolcreatedb AS crea_bases, rolbypassrls AS salta_rls, rolconnlimit AS conexiones
FROM pg_roles
WHERE rolname LIKE 'rol\_%' OR rolname IN ('fs_owner', 'app_web', 'admin_datos', 'soporte_01',
      'analista_01', 'auditor_01', 'operador_respaldo', 'tablet_feria')
ORDER BY rolcanlogin, rolname;
