-- V1: catálogo vigente. Una baja de categoría también oculta sus productos.
CREATE VIEW tp5_productos_vigentes
    (id_producto, nombre_producto, precio_lista, stock, id_categoria, nombre_categoria)
AS
SELECT p.id_producto, p.nombre, p.precio_lista, p.stock, c.id_categoria, c.nombre
FROM producto p JOIN categoria c ON c.id_categoria = p.categoria_id
WHERE p.activo AND c.activo;

-- V2: historial de todos los estados. No expone correo ni teléfono.
-- El modelo heredado no contiene contraseña; no se añade ni simula esa columna.
-- Permisos de tablas comprobados como propietario de la vista (valor predeterminado).
CREATE VIEW tp5_pedidos_clientes
    (id_pedido, fecha, estado, forma_pago, id_cliente, nombre, apellido)
AS
SELECT o.id_pedido, o.fecha, o.estado, o.forma_pago, c.id_cliente, c.nombre, c.apellido
FROM pedido o JOIN cliente c ON c.id_cliente = o.cliente_id;
