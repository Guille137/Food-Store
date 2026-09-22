-- Candidata medida y descartada: empeora A1 en la ejecucion documentada.
-- Solucion elegida: a1_antes.sql con indices.sql. Se conserva el intento para la bitacora.
SELECT c.id_categoria,c.nombre,
       date_trunc('month',o.fecha AT TIME ZONE 'UTC')::date AS mes,
       sum(d.cantidad) AS unidades,
       sum(d.cantidad*d.precio_unitario) AS importe
FROM pedido o
JOIN detalle_pedido d ON d.id_pedido=o.id_pedido
JOIN producto p ON p.id_producto=d.id_producto
JOIN categoria c ON c.id_categoria=p.categoria_id
WHERE o.estado='ENTREGADO' AND p.activo=TRUE AND c.activo=TRUE
  AND o.fecha>=TIMESTAMPTZ '2025-06-01 00:00:00+00'
  AND o.fecha<TIMESTAMPTZ '2025-07-01 00:00:00+00'
GROUP BY c.id_categoria,c.nombre,date_trunc('month',o.fecha AT TIME ZONE 'UTC')::date
ORDER BY mes,c.id_categoria;
