-- Unidad 6 · Requisito del plan de mantenimiento: extensión amcheck, usada por
-- verificar_integridad.sql para revisar la estructura interna de los índices.
-- Ejecutar una vez, como superusuario. PostgreSQL no da EXECUTE a PUBLIC sobre
-- las funciones de amcheck: solo las usa quien corre el mantenimiento.
CREATE EXTENSION IF NOT EXISTS amcheck;
SELECT extname, extversion FROM pg_extension WHERE extname IN ('amcheck', 'pgcrypto') ORDER BY 1;
