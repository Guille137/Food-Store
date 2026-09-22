-- Q1: misma consulta, índice parcial que satisface filtros y orden.
SELECT id_producto, nombre, precio_lista
FROM producto
WHERE activo=TRUE AND categoria_id=1 AND precio_lista BETWEEN 1000 AND 1500
ORDER BY precio_lista, id_producto
LIMIT 50;

-- Q2: mismo día UTC, con rango semiabierto indexable.
SELECT id_pedido, fecha, estado, cliente_id
FROM pedido
WHERE fecha >= TIMESTAMPTZ '2025-06-15 00:00:00+00'
  AND fecha < TIMESTAMPTZ '2025-06-16 00:00:00+00'
ORDER BY fecha, id_pedido;

-- Q3: misma consulta, índice por la FK buscada.
SELECT id_producto, count(*) AS lineas, sum(cantidad) AS unidades,
       sum(cantidad * precio_unitario) AS importe
FROM detalle_pedido
WHERE id_producto=4
GROUP BY id_producto;
