-- I1 / Q1: B-tree de expresión; solo productos vigentes.
-- El UNIQUE heredado sobre nombre no resuelve igualdad sobre lower(nombre).
CREATE INDEX tp5_producto_nombre_activo
ON producto (lower(nombre)) WHERE activo;

-- I2 / Q2: la cola confirmada con tarjeta ocupa solo una fracción de pedido.
-- Las claves satisfacen ORDER BY y los INCLUDE cubren la proyección.
CREATE INDEX tp5_pedido_confirmado_tarjeta
ON pedido (fecha, id_pedido) INCLUDE (estado, forma_pago, cliente_id)
WHERE estado = 'CONFIRMADO' AND forma_pago = 'TARJETA';
