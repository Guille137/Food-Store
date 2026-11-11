-- Unidad 5 · Paso 2: auditoría de operaciones a nivel de fila.
-- Complementa el log del servidor (04_config_auditoria.sql): el log dice QUÉ
-- sentencia se ejecutó; esta tabla dice QUÉ FILA cambió, de qué valor a cuál.
-- Ejecutar dentro de una transacción externa, después de 01.

CREATE TABLE auditoria.registro (
    id_registro   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    momento       timestamptz NOT NULL DEFAULT clock_timestamp(),
    rol_sesion    text NOT NULL DEFAULT session_user,   -- con quién se conectó
    rol_actual    text NOT NULL DEFAULT current_user,   -- con qué privilegios actuó
    origen        inet DEFAULT inet_client_addr(),
    aplicacion    text DEFAULT current_setting('application_name', TRUE),
    id_transaccion bigint NOT NULL DEFAULT txid_current(),
    tabla         text NOT NULL,
    operacion     text NOT NULL CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
    antes         jsonb,
    despues       jsonb
);
CREATE INDEX idx_registro_tabla_momento ON auditoria.registro (tabla, momento);
CREATE INDEX idx_registro_rol_momento ON auditoria.registro (rol_sesion, momento);

-- SECURITY DEFINER: quien modifica una tabla auditada no necesita (ni recibe)
-- permiso de escritura sobre la auditoría. El hash de la contraseña se enmascara.
CREATE FUNCTION auditoria.fn_registrar() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_antes   jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
    v_despues jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
BEGIN
    IF v_antes ? 'password_hash' THEN
        v_antes := jsonb_set(v_antes, '{password_hash}', '"***"');
    END IF;
    IF v_despues ? 'password_hash' THEN
        -- Se deja constancia de que la clave cambió, sin revelar ningún hash.
        v_despues := jsonb_set(v_despues, '{password_hash}',
            CASE WHEN TG_OP = 'UPDATE' AND OLD.password_hash IS DISTINCT FROM NEW.password_hash
                 THEN '"*** (modificada)"' ELSE '"***"' END::jsonb);
    END IF;
    -- session_user sigue siendo el rol que se conectó aunque la función sea DEFINER;
    -- el parámetro "role" indica si además hizo SET ROLE a otro rol.
    INSERT INTO auditoria.registro (rol_actual, tabla, operacion, antes, despues)
    VALUES (COALESCE(NULLIF(current_setting('role', TRUE), 'none'), session_user),
            TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
            TG_OP, v_antes, v_despues);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_auditar_usuario AFTER INSERT OR UPDATE OR DELETE ON public.usuario
FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar();
CREATE TRIGGER trg_auditar_cliente AFTER INSERT OR UPDATE OR DELETE ON public.cliente
FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar();
CREATE TRIGGER trg_auditar_producto AFTER INSERT OR UPDATE OR DELETE ON public.producto
FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar();
CREATE TRIGGER trg_auditar_categoria AFTER INSERT OR UPDATE OR DELETE ON public.categoria
FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar();
-- En pedido solo interesa el cambio de estado y los borrados; las altas quedan
-- en la propia tabla (fecha) y auditarlas fila a fila duplicaría el volumen.
CREATE TRIGGER trg_auditar_pedido_estado AFTER UPDATE OF estado ON public.pedido
FOR EACH ROW WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION auditoria.fn_registrar();
CREATE TRIGGER trg_auditar_pedido_borrado AFTER DELETE ON public.pedido
FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar();

-- La auditoría es de solo agregado: ni siquiera su dueño puede corregirla o
-- borrarla sin deshabilitar a propósito este trigger (lo que a su vez queda en
-- el log del servidor como DDL).
CREATE FUNCTION auditoria.fn_solo_agregar() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'La auditoría no admite % (solo INSERT)', TG_OP USING ERRCODE = '42501';
END;
$$;
CREATE TRIGGER trg_registro_solo_agregar BEFORE UPDATE OR DELETE OR TRUNCATE ON auditoria.registro
FOR EACH STATEMENT EXECUTE FUNCTION auditoria.fn_solo_agregar();
CREATE TRIGGER trg_intento_solo_agregar BEFORE UPDATE OR DELETE OR TRUNCATE ON auditoria.intento_login
FOR EACH STATEMENT EXECUTE FUNCTION auditoria.fn_solo_agregar();

-- Alerta: varios fallos seguidos de un ingreso exitoso sobre la misma cuenta en
-- 15 minutos. Es el patrón de "adivinaron la clave", no el de un error de tipeo.
CREATE VIEW auditoria.v_alerta_fuerza_bruta AS
SELECT ok.correo, ok.momento AS ingreso_exitoso, ok.rol_sesion, ok.origen,
       count(f.id_intento) AS fallos_previos, min(f.momento) AS primer_fallo
FROM auditoria.intento_login AS ok
JOIN auditoria.intento_login AS f
  ON f.correo = ok.correo AND NOT f.exito
 AND f.momento < ok.momento AND f.momento >= ok.momento - INTERVAL '15 minutes'
WHERE ok.exito
GROUP BY ok.id_intento, ok.correo, ok.momento, ok.rol_sesion, ok.origen
HAVING count(f.id_intento) >= 3;

CREATE VIEW auditoria.v_actividad_por_rol AS
SELECT rol_sesion, tabla, operacion, count(*) AS filas,
       min(momento) AS primera, max(momento) AS ultima
FROM auditoria.registro
GROUP BY rol_sesion, tabla, operacion;
