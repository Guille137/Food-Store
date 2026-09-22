SELECT u.id_cliente,u.nombre||' '||u.apellido AS nombre_completo,u.correo_electronico
FROM cliente u
WHERE (
  SELECT sum(d.cantidad*d.precio_unitario)
  FROM pedido o JOIN detalle_pedido d ON d.id_pedido=o.id_pedido
  WHERE o.cliente_id=u.id_cliente AND o.estado='ENTREGADO'
    AND o.fecha>=TIMESTAMPTZ '2025-01-01 00:00:00+00'
    AND o.fecha<TIMESTAMPTZ '2026-01-01 00:00:00+00'
)>50000
ORDER BY u.id_cliente ASC;
