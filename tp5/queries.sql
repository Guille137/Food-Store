-- Q1: búsqueda exacta sin distinguir mayúsculas en el catálogo vigente.
SELECT id_producto, nombre, precio_lista, stock, categoria_id
FROM producto
WHERE activo AND lower(nombre) = 'tp3 producto 12345';

-- Q2: cola de pedidos confirmados abonados con tarjeta, del más antiguo al nuevo.
SELECT id_pedido, fecha, estado, forma_pago, cliente_id
FROM pedido
WHERE estado = 'CONFIRMADO' AND forma_pago = 'TARJETA'
ORDER BY fecha, id_pedido;

-- Q3: líneas históricas de precio alto, sin excluir productos dados de baja.
SELECT id_pedido, id_producto, cantidad, precio_unitario
FROM detalle_pedido
WHERE precio_unitario >= 4990
ORDER BY precio_unitario, id_pedido, id_producto;
