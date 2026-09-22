-- A1 del TP4 extendido a todos los meses. Igual regla de catálogo y estado.
SELECT c.id_categoria, c.nombre AS nombre_categoria,
       date_trunc('month', o.fecha AT TIME ZONE 'UTC')::date AS mes,
       sum(d.cantidad) AS unidades, sum(d.cantidad * d.precio_unitario) AS importe
FROM pedido o
JOIN detalle_pedido d ON d.id_pedido = o.id_pedido
JOIN producto p ON p.id_producto = d.id_producto
JOIN categoria c ON c.id_categoria = p.categoria_id
WHERE o.estado = 'ENTREGADO' AND p.activo AND c.activo
GROUP BY c.id_categoria, c.nombre, date_trunc('month', o.fecha AT TIME ZONE 'UTC')::date
ORDER BY mes, c.id_categoria;
