WITH pedidos_totales AS (
  SELECT o.id_pedido,o.cliente_id,sum(d.cantidad*d.precio_unitario) AS total
  FROM pedido o JOIN detalle_pedido d ON d.id_pedido=o.id_pedido
  WHERE o.estado='ENTREGADO'
    AND o.fecha>=TIMESTAMPTZ '2025-01-01 00:00:00+00'
    AND o.fecha<TIMESTAMPTZ '2026-01-01 00:00:00+00'
  GROUP BY o.id_pedido,o.cliente_id
), gastos AS (
  SELECT cliente_id,sum(total) AS total_gastado FROM pedidos_totales GROUP BY cliente_id
), puestos AS (
  SELECT total_gastado,row_number() OVER(ORDER BY total_gastado DESC) AS puesto
  FROM (SELECT DISTINCT total_gastado FROM gastos) importes
)
SELECT u.id_cliente,u.nombre||' '||u.apellido AS nombre_completo,g.total_gastado,p.puesto
FROM gastos g JOIN cliente u ON u.id_cliente=g.cliente_id
JOIN puestos p ON p.total_gastado=g.total_gastado
ORDER BY p.puesto ASC,u.id_cliente ASC;
