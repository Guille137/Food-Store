-- Unidad 5 · Paso 1: usuarios internos de Food Store y autenticación.
-- "usuario" es el personal que opera el sistema (no los clientes que compran).
-- Las contraseñas nunca se guardan ni se registran en claro: solo su hash bcrypt.
-- Ejecutar dentro de una transacción externa, como dueño de la base.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE public.usuario (
    id_usuario            integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    correo_electronico    varchar(150) NOT NULL,
    nombre                varchar(50) NOT NULL,
    apellido              varchar(50) NOT NULL,
    rol_aplicacion        varchar(20) NOT NULL
        CHECK (rol_aplicacion IN ('ADMIN', 'VENTAS', 'SOPORTE', 'REPORTES')),
    password_hash         text NOT NULL,
    activo                boolean NOT NULL DEFAULT TRUE,
    fecha_alta            timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    intentos_fallidos     integer NOT NULL DEFAULT 0 CHECK (intentos_fallidos >= 0),
    bloqueado_hasta       timestamptz,
    debe_cambiar_password boolean NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_usuario_correo UNIQUE (correo_electronico),
    CONSTRAINT chk_usuario_correo_minusculas CHECK (correo_electronico = lower(correo_electronico))
);

-- 40 usuarios sintéticos. La clave de laboratorio de cada uno se deriva de su
-- número (no es un secreto real). Costo bcrypt 6 para que el laboratorio sea
-- rápido; en producción corresponde 12 o más.
INSERT INTO public.usuario (correo_electronico, nombre, apellido, rol_aplicacion, password_hash, fecha_alta)
SELECT 'usuario' || n || '@foodstore.example',
       (ARRAY['Alma','Bautista','Camila','Dante','Emma','Felipe','Guadalupe','Ian'])[1 + n % 8],
       (ARRAY['Arias','Blanco','Correa','Diaz','Flores'])[1 + n % 5],
       (ARRAY['VENTAS','VENTAS','VENTAS','SOPORTE','REPORTES','ADMIN'])[1 + n % 6],
       crypt('Lab-' || substr(md5('clave' || n), 1, 10), gen_salt('bf', 6)),
       TIMESTAMPTZ '2026-01-05 09:00-03' + make_interval(days => (n * 7) % 280)
FROM generate_series(1, 40) AS n;
UPDATE public.usuario SET activo = FALSE WHERE id_usuario IN (13, 27);

-- Esquema de auditoría: lo que pasa con la autenticación queda en una tabla,
-- no solo en el log de texto del servidor.
CREATE SCHEMA auditoria;

CREATE TABLE auditoria.intento_login (
    id_intento   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    momento      timestamptz NOT NULL DEFAULT clock_timestamp(),
    correo       text NOT NULL,          -- el correo intentado, exista o no
    exito        boolean NOT NULL,
    motivo       text NOT NULL,
    rol_sesion   text NOT NULL DEFAULT session_user,
    origen       inet DEFAULT inet_client_addr(),
    aplicacion   text DEFAULT current_setting('application_name', TRUE)
);
CREATE INDEX idx_intento_login_correo_momento ON auditoria.intento_login (correo, momento);

-- Autentica sin exponer la tabla usuario: quien la llama no necesita (ni tiene)
-- SELECT sobre usuario. Nunca lanza excepción por credenciales inválidas, para
-- que la contraseña recibida no termine en el log de errores del servidor.
-- Tras 5 fallos consecutivos bloquea la cuenta 15 minutos.
CREATE FUNCTION public.fn_autenticar(p_correo text, p_password text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_usuario public.usuario%ROWTYPE;
    v_correo  text := lower(btrim(p_correo));
BEGIN
    SELECT * INTO v_usuario FROM public.usuario
    WHERE correo_electronico = v_correo
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Mismo trabajo de hash que en el camino normal: no delata qué correos existen.
        PERFORM crypt(p_password, gen_salt('bf', 6));
        INSERT INTO auditoria.intento_login (correo, exito, motivo)
        VALUES (v_correo, FALSE, 'USUARIO_INEXISTENTE');
        RETURN FALSE;
    END IF;

    IF NOT v_usuario.activo THEN
        -- Mismo costo que una clave incorrecta (hallazgo H5): sin diferencia de tiempo.
        PERFORM crypt(p_password, v_usuario.password_hash);
        INSERT INTO auditoria.intento_login (correo, exito, motivo)
        VALUES (v_correo, FALSE, 'USUARIO_INACTIVO');
        RETURN FALSE;
    END IF;

    IF v_usuario.bloqueado_hasta IS NOT NULL AND v_usuario.bloqueado_hasta > clock_timestamp() THEN
        PERFORM crypt(p_password, v_usuario.password_hash);
        INSERT INTO auditoria.intento_login (correo, exito, motivo)
        VALUES (v_correo, FALSE, 'CUENTA_BLOQUEADA');
        RETURN FALSE;
    END IF;

    IF v_usuario.password_hash = crypt(p_password, v_usuario.password_hash) THEN
        UPDATE public.usuario SET intentos_fallidos = 0, bloqueado_hasta = NULL
        WHERE id_usuario = v_usuario.id_usuario;
        INSERT INTO auditoria.intento_login (correo, exito, motivo)
        VALUES (v_correo, TRUE, 'OK');
        RETURN TRUE;
    END IF;

    UPDATE public.usuario
    SET intentos_fallidos = intentos_fallidos + 1,
        bloqueado_hasta = CASE WHEN intentos_fallidos + 1 >= 5
                               THEN clock_timestamp() + INTERVAL '15 minutes' END
    WHERE id_usuario = v_usuario.id_usuario;
    INSERT INTO auditoria.intento_login (correo, exito, motivo)
    VALUES (v_correo, FALSE, 'PASSWORD_INCORRECTA');
    RETURN FALSE;
END;
$$;

-- Restablece la clave: genera una temporal al azar, la devuelve UNA vez y obliga
-- a cambiarla. No recibe la clave nueva como parámetro, así no viaja en la
-- sentencia SQL (que el log de auditoría sí registra).
CREATE FUNCTION public.fn_resetear_password(p_correo text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_temporal text := translate(encode(gen_random_bytes(12), 'base64'), '+/=', 'xyz');
BEGIN
    UPDATE public.usuario
    SET password_hash = crypt(v_temporal, gen_salt('bf', 6)),
        debe_cambiar_password = TRUE, intentos_fallidos = 0, bloqueado_hasta = NULL
    WHERE correo_electronico = lower(btrim(p_correo));
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuario inexistente' USING ERRCODE = 'P0002';
    END IF;
    RETURN v_temporal;
END;
$$;

SELECT rol_aplicacion, count(*) AS usuarios, count(*) FILTER (WHERE activo) AS activos
FROM public.usuario GROUP BY 1 ORDER BY 1;
