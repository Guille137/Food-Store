WITH gastos AS (
  SELECT u.id_cliente,u.nombre||' '||u.apellido AS nombre_completo,
         sum(d.cantidad*d.precio_unitario) AS total_gastado
  FROM cliente u JOIN pedido o ON o.cliente_id=u.id_cliente
  JOIN detalle_pedido d ON d.id_pedido=o.id_pedido
  WHERE o.estado='ENTREGADO'
    AND o.fecha>=TIMESTAMPTZ '2025-01-01 00:00:00+00'
    AND o.fecha<TIMESTAMPTZ '2026-01-01 00:00:00+00'
  GROUP BY u.id_cliente,u.nombre,u.apellido
)
SELECT id_cliente,nombre_completo,total_gastado,
       dense_rank() OVER (ORDER BY total_gastado DESC) AS puesto
FROM gastos
ORDER BY puesto ASC,id_cliente ASC;
