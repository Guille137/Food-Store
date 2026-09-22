-- Propuestas motivadas por los planes iniciales: ver propuestas_ia.md.
-- Se añaden a los índices del TP3, sin eliminar restricciones.
CREATE INDEX tp4_pedido_entregado_fecha
ON pedido(fecha,id_pedido) INCLUDE(cliente_id) WHERE estado='ENTREGADO';

CREATE INDEX tp4_detalle_pedido_cubierto
ON detalle_pedido(id_pedido) INCLUDE(id_producto,cantidad,precio_unitario);
