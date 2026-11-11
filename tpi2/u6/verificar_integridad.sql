-- Unidad 6 · Verificación de integridad física y lógica.
-- Se ejecuta en el mantenimiento semanal y después de CADA restauración.
-- Solo lectura. Si un control falla, lanza una excepción (psql termina con error).
-- Requiere la extensión amcheck (00_instalar.sql) y un rol superusuario.
\set ON_ERROR_STOP on

\echo 'I1. Índices B-tree: estructura interna (amcheck)'
SELECT count(*) AS indices_revisados
FROM (
    SELECT bt_index_check(c.oid, TRUE)      -- TRUE: además comprueba que cada fila de la tabla esté en el índice
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    JOIN pg_am am ON am.oid = c.relam
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE am.amname = 'btree' AND i.indisvalid AND c.relpersistence = 'p'
      AND n.nspname IN ('public', 'unidad4', 'auditoria', 'seguridad', 'anon', 'sync', 'migracion')
) AS x;

\echo 'I2. Sumas de verificación de páginas (data checksums)'
SELECT current_setting('data_checksums') AS checksums_activos,
       COALESCE(checksum_failures, 0) AS fallas_detectadas, checksum_last_failure
FROM pg_stat_database WHERE datname = current_database();

\echo 'I3. Objetos en estado inválido'
SELECT (SELECT count(*) FROM pg_index WHERE NOT indisvalid) AS indices_invalidos,
       (SELECT count(*) FROM pg_constraint WHERE NOT convalidated) AS restricciones_sin_validar,
       (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgenabled = 'D') AS triggers_deshabilitados,
       (SELECT count(*) FROM pg_class WHERE relkind = 'm' AND NOT relispopulated) AS materializadas_sin_datos;

\echo 'I4. Reglas del negocio que ninguna restricción declarativa cubre'
SELECT (SELECT count(*) FROM pedido p WHERE NOT EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.id_pedido = p.id_pedido)
            AND p.estado IN ('CONFIRMADO', 'ENTREGADO')) AS pedidos_confirmados_sin_lineas,
       (SELECT count(*) FROM unidad4.auditoria_ventas) AS desnormalizacion_desincronizada,
       (SELECT count(*) FROM seguridad.v_equivalencia_usuario) AS copia_anonima_desactualizada,
       (SELECT count(*) FROM usuario WHERE password_hash !~ '^\$2[aby]\$') AS claves_sin_hash,
       (SELECT count(*) FROM sync.solicitud WHERE estado = 'EN_PROCESO') AS solicitudes_sin_resolver;

\echo 'I5. Conteos de control'
SELECT (SELECT count(*) FROM categoria) AS categorias, (SELECT count(*) FROM producto) AS productos,
       (SELECT count(*) FROM cliente) AS clientes, (SELECT count(*) FROM pedido) AS pedidos,
       (SELECT count(*) FROM detalle_pedido) AS lineas,
       (SELECT sum(cantidad * precio_unitario) FROM detalle_pedido) AS importe_total,
       (SELECT count(*) FROM usuario) AS usuarios, (SELECT count(*) FROM auditoria.registro) AS filas_auditoria;

DO $$
DECLARE v text := '';
BEGIN
    IF current_setting('data_checksums') <> 'on' THEN
        v := v || ' [checksums de datos desactivados]';
    END IF;
    IF (SELECT COALESCE(checksum_failures, 0) FROM pg_stat_database WHERE datname = current_database()) > 0 THEN
        v := v || ' [páginas con checksum incorrecto]';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_index WHERE NOT indisvalid) THEN v := v || ' [índices inválidos]'; END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE NOT convalidated) THEN v := v || ' [restricciones sin validar]'; END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal AND tgenabled = 'D') THEN
        v := v || ' [triggers deshabilitados]';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_class WHERE relkind = 'm' AND NOT relispopulated) THEN
        v := v || ' [materializadas sin datos]';
    END IF;
    IF EXISTS (SELECT 1 FROM unidad4.auditoria_ventas) THEN v := v || ' [desnormalización desincronizada]'; END IF;
    IF EXISTS (SELECT 1 FROM usuario WHERE password_hash !~ '^\$2[aby]\$') THEN v := v || ' [claves sin hash]'; END IF;
    IF EXISTS (SELECT 1 FROM sync.solicitud WHERE estado = 'EN_PROCESO') THEN
        v := v || ' [solicitudes de sincronización sin resolver]';
    END IF;
    IF v <> '' THEN
        RAISE EXCEPTION 'INTEGRIDAD CON PROBLEMAS:%', v;
    END IF;
    -- La copia anónima vieja no es corrupción: se avisa y se corrige con el REFRESH semanal.
    IF EXISTS (SELECT 1 FROM seguridad.v_equivalencia_usuario) THEN
        RAISE WARNING 'La copia anónima está desactualizada: ejecutar mantenimiento.sql';
    END IF;
    RAISE NOTICE 'INTEGRIDAD VERIFICADA en %', current_database();
END $$;
