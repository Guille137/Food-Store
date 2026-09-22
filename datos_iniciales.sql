-- Datos sintéticos del laboratorio. Ejecutar UNA VEZ sobre schema.sql recién creado.
-- La base debe estar vacía; los ids explícitos hacen reproducibles los ejemplos.
INSERT INTO categoria (id_categoria, nombre) OVERRIDING SYSTEM VALUE
VALUES (1, 'Pizzas'), (2, 'Bebidas'), (3, 'Sin productos');

INSERT INTO cliente (id_cliente, correo_electronico, nombre, apellido)
OVERRIDING SYSTEM VALUE
VALUES (1, 'cliente1@example.test', 'Ana', 'Prueba');

INSERT INTO producto (id_producto, nombre, precio_lista, stock, activo, categoria_id)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Muzzarella de prueba', 1000, 10, TRUE, 1),
       (2, 'Bebida inactiva de prueba', 800, 10, FALSE, 2),
       (3, 'Bebida activa de prueba', 900, 5, TRUE, 2);

INSERT INTO pedido (id_pedido, forma_pago, cliente_id) OVERRIDING SYSTEM VALUE
VALUES (1, 'EFECTIVO', 1), (2, 'TARJETA', 1), (3, 'TRANSFERENCIA', 1);

-- Ajustar las secuencias tras usar OVERRIDING SYSTEM VALUE.
SELECT setval(pg_get_serial_sequence('categoria', 'id_categoria'), 3);
SELECT setval(pg_get_serial_sequence('cliente', 'id_cliente'), 1);
SELECT setval(pg_get_serial_sequence('producto', 'id_producto'), 3);
SELECT setval(pg_get_serial_sequence('pedido', 'id_pedido'), 3);
