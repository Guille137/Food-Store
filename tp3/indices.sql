-- Candidatos derivados de los planes reales: ver propuestas_ia.md.
-- Ejecutar en la copia, con respaldo previo y un ensayo BEGIN ... ROLLBACK.
CREATE INDEX tp3_producto_categoria_precio
ON producto(categoria_id, precio_lista, id_producto)
INCLUDE(nombre) WHERE activo=TRUE;

CREATE INDEX tp3_pedido_fecha
ON pedido(fecha, id_pedido) INCLUDE(estado, cliente_id);

CREATE INDEX tp3_detalle_producto
ON detalle_pedido(id_producto) INCLUDE(cantidad, precio_unitario);
