SELECT u.id_cliente,u.nombre,u.apellido,g.total_gastado
FROM (
  SELECT o.cliente_id,sum(d.cantidad*d.precio_unitario) AS total_gastado
  FROM pedido o
  JOIN detalle_pedido d ON d.id_pedido=o.id_pedido
  WHERE o.estado='ENTREGADO'
    AND o.fecha>=TIMESTAMPTZ '2025-01-01 00:00:00+00'
    AND o.fecha<TIMESTAMPTZ '2026-01-01 00:00:00+00'
  GROUP BY o.cliente_id
) g
JOIN cliente u ON u.id_cliente=g.cliente_id
ORDER BY g.total_gastado DESC,u.id_cliente ASC
LIMIT 50;
