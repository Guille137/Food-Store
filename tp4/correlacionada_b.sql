SELECT u.id_cliente,u.nombre||' '||u.apellido AS nombre_completo,u.correo_electronico
FROM cliente u JOIN pedido o ON o.cliente_id=u.id_cliente
JOIN detalle_pedido d ON d.id_pedido=o.id_pedido
WHERE o.estado='ENTREGADO'
  AND o.fecha>=TIMESTAMPTZ '2025-01-01 00:00:00+00'
  AND o.fecha<TIMESTAMPTZ '2026-01-01 00:00:00+00'
GROUP BY u.id_cliente,u.nombre,u.apellido,u.correo_electronico
HAVING sum(d.cantidad*d.precio_unitario)>50000
ORDER BY u.id_cliente ASC;
