-- Facturación del catálogo vigente, por categoría y mes UTC: extensión de A1/TP4.
-- Una baja posterior del catálogo modifica el resultado al refrescar.
CREATE MATERIALIZED VIEW tp5_facturacion_mensual
    (id_categoria, nombre_categoria, mes, unidades, importe)
AS
SELECT c.id_categoria, c.nombre,
       date_trunc('month', o.fecha AT TIME ZONE 'UTC')::date,
       sum(d.cantidad), sum(d.cantidad * d.precio_unitario)
FROM pedido o
JOIN detalle_pedido d ON d.id_pedido = o.id_pedido
JOIN producto p ON p.id_producto = d.id_producto
JOIN categoria c ON c.id_categoria = p.categoria_id
WHERE o.estado = 'ENTREGADO' AND p.activo AND c.activo
GROUP BY c.id_categoria, c.nombre, date_trunc('month', o.fecha AT TIME ZONE 'UTC')::date
WITH DATA;
