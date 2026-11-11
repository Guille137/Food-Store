-- Unidad 5 · Paso 5: activar la auditoría de accesos en el servidor.
-- Ejecutar como superusuario, FUERA de una transacción (ALTER SYSTEM no admite
-- BEGIN). Escribe en postgresql.auto.conf y recarga la configuración; no hace
-- falta reiniciar. Requisito previo, que sí exige reinicio y por eso se deja en
-- postgresql.conf al crear el servidor: logging_collector = on.
\set ON_ERROR_STOP on

ALTER SYSTEM SET log_connections = 'on';        -- quién entra, desde dónde, con qué método
ALTER SYSTEM SET log_disconnections = 'on';     -- cuándo sale y cuánto duró la sesión
ALTER SYSTEM SET log_statement = 'mod';         -- toda escritura y todo DDL (incluye GRANT/REVOKE)
-- Cada línea identifica momento, proceso, rol, base, origen y aplicación.
ALTER SYSTEM SET log_line_prefix = '%m [%p] rol=%u base=%d origen=%h app=%a ';
-- Las sentencias que fallan (permiso denegado, etc.) quedan con su texto.
ALTER SYSTEM SET log_min_error_statement = 'error';
-- Los valores de los parámetros enlazados NO se escriben en el log, ni en la
-- sentencia ni en el error: así una contraseña enviada como parámetro no queda
-- registrada.
ALTER SYSTEM SET log_parameter_max_length = 0;
ALTER SYSTEM SET log_parameter_max_length_on_error = 0;
ALTER SYSTEM SET password_encryption = 'scram-sha-256';

SELECT pg_reload_conf() AS recargado;
SELECT pg_sleep(1);
-- log_connections solo se lee al iniciar una sesión: se reconecta para mostrar el valor vigente.
\connect -

SELECT name AS parametro, setting AS valor, source AS origen, pending_restart AS requiere_reinicio
FROM pg_settings
WHERE name IN ('logging_collector', 'log_connections', 'log_disconnections', 'log_statement',
               'log_line_prefix', 'log_min_error_statement', 'log_parameter_max_length',
               'log_parameter_max_length_on_error', 'password_encryption', 'log_destination',
               'log_directory', 'data_checksums')
ORDER BY name;

-- Ajustes por rol (definidos en 04_roles.sql): las personas registran también lecturas.
SELECT r.rolname AS rol, unnest(s.setconfig) AS ajuste
FROM pg_db_role_setting AS s JOIN pg_roles AS r ON r.oid = s.setrole
ORDER BY 1;
