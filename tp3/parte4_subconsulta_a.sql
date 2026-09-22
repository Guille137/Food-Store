SELECT p.id_producto, p.nombre, p.precio_lista
FROM producto p
JOIN categoria c ON c.id_categoria=p.categoria_id
WHERE p.activo=TRUE AND c.activo=TRUE
  AND NOT EXISTS (
    SELECT 1 FROM detalle_pedido d
    JOIN pedido o ON o.id_pedido=d.id_pedido
    WHERE d.id_producto=p.id_producto AND o.estado<>'CANCELADO'
  )
ORDER BY p.id_producto ASC;
