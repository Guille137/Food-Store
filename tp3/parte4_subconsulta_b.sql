SELECT p.id_producto, p.nombre, p.precio_lista
FROM producto p
JOIN categoria c ON c.id_categoria=p.categoria_id
LEFT JOIN (
  SELECT DISTINCT d.id_producto
  FROM detalle_pedido d
  JOIN pedido o ON o.id_pedido=d.id_pedido
  WHERE o.estado<>'CANCELADO'
) vendidos ON vendidos.id_producto=p.id_producto
WHERE p.activo=TRUE AND c.activo=TRUE AND vendidos.id_producto IS NULL
ORDER BY p.id_producto ASC;
