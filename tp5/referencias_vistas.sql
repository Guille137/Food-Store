-- Parte B: consultas de contraste sobre las tablas base, sin consultar las vistas.
-- El ORDER BY de cada consulta coincide con el usado al verificar su vista.
-- V1: primero limitar las categorías, después obtener sus productos vigentes.
WITH categorias_vigentes AS (
    SELECT id_categoria, nombre FROM categoria WHERE activo
)
SELECT p.id_producto, p.nombre AS nombre_producto, p.precio_lista, p.stock,
       c.id_categoria, c.nombre AS nombre_categoria
FROM categorias_vigentes c JOIN producto p ON p.categoria_id = c.id_categoria
WHERE p.activo
ORDER BY p.id_producto;

-- V2: proyectar primero la información pública de los clientes.
WITH personas AS (
    SELECT id_cliente, nombre, apellido FROM cliente
)
SELECT o.id_pedido, o.fecha, o.estado, o.forma_pago, u.id_cliente, u.nombre, u.apellido
FROM personas u JOIN pedido o ON o.cliente_id = u.id_cliente
ORDER BY o.id_pedido;

-- V3: la PK garantiza que la subconsulta escalar devuelve exactamente un nombre.
SELECT d.id_pedido, d.id_producto,
       (SELECT p.nombre FROM producto p WHERE p.id_producto = d.id_producto) AS nombre_producto,
       d.cantidad, d.precio_unitario, d.cantidad * d.precio_unitario AS subtotal
FROM detalle_pedido d
ORDER BY d.id_pedido, d.id_producto;
