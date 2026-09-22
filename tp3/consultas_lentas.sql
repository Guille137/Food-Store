-- Variantes propias sobre el esquema del proyecto, permitidas por la consigna.
-- Q1: productos vigentes por categoría, rango de precio y orden estable.
SELECT id_producto, nombre, precio_lista
FROM producto
WHERE activo=TRUE AND categoria_id=1 AND precio_lista BETWEEN 1000 AND 1500
ORDER BY precio_lista, id_producto
LIMIT 50;

-- Q2: historial en una fecha civil UTC. La conversión de fecha dificulta el índice común.
SELECT id_pedido, fecha, estado, cliente_id
FROM pedido
WHERE (fecha AT TIME ZONE 'UTC')::date = DATE '2025-06-15'
ORDER BY fecha, id_pedido;

-- Q3: unidades e importe histórico de un producto; PK comienza por id_pedido.
SELECT id_producto, count(*) AS lineas, sum(cantidad) AS unidades,
       sum(cantidad * precio_unitario) AS importe
FROM detalle_pedido
WHERE id_producto=4
GROUP BY id_producto;
