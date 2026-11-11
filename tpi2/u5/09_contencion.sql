-- Unidad 5 · Paso 9: PROPUESTA de contención del incidente simulado.
-- Este archivo es una propuesta redactada con asistencia de IA. Ejecutarlo en un
-- caso real es una decisión de las personas responsables (ver informe_incidente.md);
-- acá se ejecuta únicamente en el laboratorio para probar que funciona.
-- Ejecutar como superusuario, dentro de una transacción externa.
-- Variables: :'rol_comprometido'  :'correo_victima'

-- C1. Cortar el acceso: el rol comprometido deja de poder conectarse y se
--     cierran sus sesiones abiertas.
SELECT format('ALTER ROLE %I NOLOGIN', :'rol_comprometido') \gexec
SELECT pid, usename, application_name, client_addr, pg_terminate_backend(pid) AS sesion_cerrada
FROM pg_stat_activity WHERE usename = :'rol_comprometido';

-- C2. La cuenta de aplicación adivinada: clave nueva al azar y cambio obligatorio.
--     (La clave temporal se entrega por un canal seguro; no se muestra acá.)
SELECT length(public.fn_resetear_password(:'correo_victima')) AS largo_clave_temporal;

-- C3. Revertir lo que el rol comprometido modificó, usando el valor "antes"
--     guardado por la auditoría. Solo teléfonos de cliente: es lo único que
--     ese rol puede escribir, además del estado de pedidos.
WITH cambios AS (
    SELECT DISTINCT ON ((antes ->> 'id_cliente')::integer)
           (antes ->> 'id_cliente')::integer AS id_cliente, antes ->> 'nro_telefono' AS telefono_original
    FROM auditoria.registro
    WHERE rol_sesion = :'rol_comprometido' AND tabla = 'public.cliente' AND operacion = 'UPDATE'
      AND momento >= :'desde'::timestamptz
    ORDER BY (antes ->> 'id_cliente')::integer, momento      -- el primer "antes" es el valor legítimo
)
UPDATE public.cliente AS c SET nro_telefono = cambios.telefono_original
FROM cambios WHERE c.id_cliente = cambios.id_cliente
RETURNING c.id_cliente, 'teléfono restaurado' AS accion;

-- C4. Alcance de la exposición, para el aviso a las personas afectadas.
SELECT count(*) FILTER (WHERE tabla = 'public.cliente') AS clientes_modificados,
       count(*) FILTER (WHERE tabla = 'public.pedido') AS pedidos_modificados
FROM auditoria.registro
WHERE rol_sesion = :'rol_comprometido' AND momento >= :'desde'::timestamptz;
