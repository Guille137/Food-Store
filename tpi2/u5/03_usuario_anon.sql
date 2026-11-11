-- Unidad 5 · Paso 3: datos anonimizados para reportes y para trabajar con IA.
-- Regla del protocolo: a un asistente de IA nunca se le envían correos, nombres,
-- teléfonos ni hashes. Lo que sale de la base sale por estas vistas.
-- Son vistas MATERIALIZADAS: quien las consulta no necesita permiso sobre las
-- tablas reales ni sobre la función de seudónimos, y un cambio posterior en los
-- datos reales no se filtra hasta el próximo REFRESH (plan de mantenimiento U6).
-- Técnicas: seudónimo determinista (misma persona -> mismo seudónimo, no
-- reversible sin la sal), supresión (nombre, teléfono, hash) y generalización
-- (fecha de alta -> mes).
-- Ejecutar dentro de una transacción externa, después de 01.

-- Dos esquemas: "seguridad" guarda la sal y la función (nadie más los lee);
-- "anon" contiene solo objetos aptos para salir de la base.
CREATE SCHEMA seguridad;
CREATE SCHEMA anon;
COMMENT ON SCHEMA anon IS 'Solo vistas anonimizadas. Todo lo que hay acá puede compartirse.';

-- La sal vive en la base y solo la lee el dueño de las vistas.
CREATE TABLE seguridad.sal (
    unica boolean PRIMARY KEY DEFAULT TRUE CHECK (unica),
    valor text NOT NULL
);
INSERT INTO seguridad.sal (valor) VALUES (encode(gen_random_bytes(16), 'hex'));

CREATE FUNCTION seguridad.seudonimo(p_prefijo text, p_id integer) RETURNS text
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
    SELECT p_prefijo || '_' || substr(encode(digest(p_id::text || ':' || s.valor, 'sha256'), 'hex'), 1, 12)
    FROM seguridad.sal AS s
$$;

CREATE MATERIALIZED VIEW anon.usuario_anon AS
SELECT seguridad.seudonimo('usr', u.id_usuario) AS usuario_anon,
       seguridad.seudonimo('usr', u.id_usuario) || '@anon.invalid' AS correo_anon,
       u.rol_aplicacion,
       u.activo,
       date_trunc('month', u.fecha_alta AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta
FROM public.usuario AS u;

CREATE MATERIALIZED VIEW anon.cliente_anon AS
SELECT seguridad.seudonimo('cli', c.id_cliente) AS cliente_anon,
       seguridad.seudonimo('cli', c.id_cliente) || '@anon.invalid' AS correo_anon,
       (c.nro_telefono IS NOT NULL) AS tiene_telefono
FROM public.cliente AS c;

CREATE UNIQUE INDEX uq_usuario_anon ON anon.usuario_anon (usuario_anon);
CREATE UNIQUE INDEX uq_cliente_anon ON anon.cliente_anon (cliente_anon);

-- Pedidos con el cliente seudonimizado: alcanza para cualquier análisis de ventas.
CREATE MATERIALIZED VIEW anon.pedido_anon AS
SELECT p.id_pedido, p.fecha, p.estado, p.forma_pago,
       seguridad.seudonimo('cli', p.cliente_id) AS cliente_anon
FROM public.pedido AS p;

CREATE UNIQUE INDEX uq_pedido_anon ON anon.pedido_anon (id_pedido);

-- Verificación de equivalencia: el agregado sobre la copia anónima debe ser
-- idéntico al agregado sobre la tabla real. Devuelve 0 filas si coinciden; si
-- devuelve filas, la copia quedó vieja (falta REFRESH) o la anonimización
-- distorsionó los datos.
CREATE VIEW seguridad.v_equivalencia_usuario AS
WITH real AS (
    SELECT rol_aplicacion,
           date_trunc('month', fecha_alta AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
           count(*) AS usuarios, count(*) FILTER (WHERE activo) AS activos
    FROM public.usuario GROUP BY 1, 2
), anon AS (
    SELECT rol_aplicacion, mes_alta, count(*) AS usuarios, count(*) FILTER (WHERE activo) AS activos
    FROM anon.usuario_anon GROUP BY 1, 2
)
(SELECT 'solo_en_real' AS origen, * FROM (SELECT * FROM real EXCEPT ALL SELECT * FROM anon) AS a)
UNION ALL
(SELECT 'solo_en_anon', * FROM (SELECT * FROM anon EXCEPT ALL SELECT * FROM real) AS b);
