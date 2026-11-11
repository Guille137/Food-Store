-- Unidad 7 · Consultas relacionales equivalentes a 04_consultas.js.
-- Devuelve UN documento JSON con el resultado de cada consulta (mismo formato
-- que la versión MongoDB) y la mediana de 30 ejecuciones medida dentro del motor.
-- Uso: psql -X -At -d BASE -f tpi2/u7/05_consultas.sql
-- Solo lectura. Usa una función temporal (pg_temp) que desaparece al cerrar la sesión.

CREATE FUNCTION pg_temp.mediana_ms(p_sql text, p_n integer) RETURNS numeric
LANGUAGE plpgsql AS $$
DECLARE t numeric[] := '{}'; a timestamptz; r record;
BEGIN
    FOR i IN 1..p_n LOOP
        a := clock_timestamp();
        FOR r IN EXECUTE p_sql LOOP END LOOP;      -- recorre todas las filas, como el cliente
        t := t || (extract(epoch FROM clock_timestamp() - a) * 1000)::numeric;
    END LOOP;
    RETURN round((SELECT x FROM unnest(t) AS x ORDER BY x OFFSET p_n / 2 LIMIT 1), 3);
END $$;

CREATE TEMP TABLE consulta (nombre text PRIMARY KEY, sql text NOT NULL);
INSERT INTO consulta VALUES
-- C1. Pedido completo: cabecera + cliente + líneas (tres JOIN).
('c1_pedido_completo', $q$
 SELECT json_build_object('id_pedido', p.id_pedido, 'estado', p.estado, 'cliente', p.cliente_id,
        'total', to_char(sum(d.cantidad * d.precio_unitario), 'FM9999999990.00'),
        'lineas', json_agg(json_build_array(d.id_producto, d.cantidad, to_char(d.precio_unitario, 'FM9999999990.00'))
                           ORDER BY d.id_producto)) AS r
 FROM pedido p JOIN cliente c ON c.id_cliente = p.cliente_id
 JOIN detalle_pedido d ON d.id_pedido = p.id_pedido
 WHERE p.id_pedido = 1500 GROUP BY p.id_pedido $q$),
-- C2. Pedidos por estado (solo pedidos con líneas, como en la colección).
('c2_pedidos_por_estado', $q$
 SELECT COALESCE(json_agg(json_build_array(estado, n) ORDER BY estado::text), '[]') AS r
 FROM (SELECT p.estado, count(*) AS n FROM pedido p
       WHERE EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.id_pedido = p.id_pedido)
       GROUP BY p.estado) x $q$),
-- C3. Pedidos que incluyen el producto 1.
('c3_pedidos_con_producto', $q$
 SELECT json_build_object('cantidad', count(*), 'ids', COALESCE(json_agg(id_pedido ORDER BY id_pedido), '[]')) AS r
 FROM detalle_pedido WHERE id_producto = 1 $q$),
-- C4. Entregados con total > 20000.
('c4_entregados_total_alto', $q$
 SELECT COALESCE(json_agg(json_build_array(id_pedido, to_char(total, 'FM9999999990.00')) ORDER BY total DESC, id_pedido), '[]') AS r
 FROM (SELECT p.id_pedido, sum(d.cantidad * d.precio_unitario) AS total
       FROM pedido p JOIN detalle_pedido d ON d.id_pedido = p.id_pedido
       WHERE p.estado = 'ENTREGADO' GROUP BY p.id_pedido HAVING sum(d.cantidad * d.precio_unitario) > 20000) x $q$),
-- C5. Facturación por categoría y mes (hora de Buenos Aires).
('c5_facturacion_categoria_mes', $q$
 SELECT COALESCE(json_agg(json_build_array(categoria, mes, to_char(importe, 'FM9999999990.00'), unidades)
                 ORDER BY categoria COLLATE "C", mes), '[]') AS r
 FROM (SELECT c.nombre AS categoria, to_char(p.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires', 'YYYY-MM') AS mes,
              sum(d.cantidad * d.precio_unitario) AS importe, sum(d.cantidad) AS unidades
       FROM pedido p JOIN detalle_pedido d ON d.id_pedido = p.id_pedido
       JOIN producto pr ON pr.id_producto = d.id_producto JOIN categoria c ON c.id_categoria = pr.categoria_id
       WHERE p.estado = 'ENTREGADO' GROUP BY 1, 2) x $q$),
-- C6. Top 5 clientes por gasto.
('c6_top_clientes', $q$
 SELECT COALESCE(json_agg(json_build_array(cliente_id, to_char(gastado, 'FM9999999990.00'), pedidos) ORDER BY gastado DESC, cliente_id), '[]') AS r
 FROM (SELECT p.cliente_id, sum(d.cantidad * d.precio_unitario) AS gastado, count(DISTINCT p.id_pedido) AS pedidos
       FROM pedido p JOIN detalle_pedido d ON d.id_pedido = p.id_pedido
       WHERE p.estado = 'ENTREGADO' GROUP BY p.cliente_id
       ORDER BY gastado DESC, p.cliente_id LIMIT 5) x $q$),
-- C7. Historial del cliente 7.
('c7_historial_cliente', $q$
 SELECT COALESCE(json_agg(json_build_array(id_pedido, to_char(total, 'FM9999999990.00')) ORDER BY fecha DESC), '[]') AS r
 FROM (SELECT p.id_pedido, p.fecha, sum(d.cantidad * d.precio_unitario) AS total
       FROM pedido p JOIN detalle_pedido d ON d.id_pedido = p.id_pedido
       WHERE p.cliente_id = 7 GROUP BY p.id_pedido) x $q$),
-- C8. Ticket promedio por forma de pago.
('c8_ticket_por_forma_pago', $q$
 SELECT COALESCE(json_agg(json_build_array(forma_pago, pedidos, to_char(round(promedio, 2), 'FM9999999990.00')) ORDER BY forma_pago::text), '[]') AS r
 FROM (SELECT forma_pago, count(*) AS pedidos, avg(total) AS promedio
       FROM (SELECT p.id_pedido, p.forma_pago, sum(d.cantidad * d.precio_unitario) AS total
             FROM pedido p JOIN detalle_pedido d ON d.id_pedido = p.id_pedido
             WHERE p.estado <> 'CANCELADO' GROUP BY p.id_pedido) t
       GROUP BY forma_pago) x $q$);

CREATE FUNCTION pg_temp.resultado(p_sql text) RETURNS json LANGUAGE plpgsql AS $$
DECLARE r json; BEGIN EXECUTE p_sql INTO r; RETURN r; END $$;

SELECT json_build_object('consultas', json_object_agg(nombre, json_build_object(
           'resultado', pg_temp.resultado(sql),
           'mediana_ms', pg_temp.mediana_ms(sql, 30))))
FROM consulta;
