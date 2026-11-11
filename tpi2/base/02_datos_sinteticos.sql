-- Datos sintéticos deterministas para la segunda entrega.
-- No usa random(): cada valor sale de md5(), así dos instalaciones producen
-- exactamente las mismas filas y las evidencias son comparables.
-- Correos @example.test y teléfonos 5555 no pertenecen a personas reales.

-- Entero no negativo y estable derivado de un texto.
CREATE FUNCTION pg_temp.h(t text) RETURNS integer
LANGUAGE sql IMMUTABLE AS $$ SELECT ('x' || substr(md5(t), 1, 7))::bit(28)::integer $$;

INSERT INTO categoria (nombre) VALUES
    ('Pizzas'), ('Empanadas'), ('Hamburguesas'), ('Bebidas'),
    ('Postres'), ('Ensaladas'), ('Pastas'), ('Sandwiches');

-- 10 productos por categoría: 80 productos.
INSERT INTO producto (nombre, precio_lista, stock, categoria_id)
SELECT c.singular || ' variedad ' || lpad(n::text, 2, '0'),
       800 + (pg_temp.h('precio' || c.id_categoria || '-' || n) % 80) * 50,
       100 + pg_temp.h('stock' || c.id_categoria || '-' || n) % 400,
       c.id_categoria
FROM (SELECT id_categoria,
             CASE nombre WHEN 'Pizzas' THEN 'Pizza' WHEN 'Empanadas' THEN 'Empanada'
                         WHEN 'Hamburguesas' THEN 'Hamburguesa' WHEN 'Bebidas' THEN 'Bebida'
                         WHEN 'Postres' THEN 'Postre' WHEN 'Ensaladas' THEN 'Ensalada'
                         WHEN 'Pastas' THEN 'Pasta' ELSE 'Sandwich' END AS singular
      FROM categoria) AS c
CROSS JOIN generate_series(1, 10) AS n
ORDER BY c.id_categoria, n;

-- 300 clientes.
INSERT INTO cliente (correo_electronico, nro_telefono, nombre, apellido)
SELECT 'cliente' || n || '@example.test',
       '+54 9 11 5555-' || lpad(n::text, 4, '0'),
       (ARRAY['Ana','Bruno','Carla','Diego','Elena','Fabio','Gala','Hugo','Irene','Joaquin',
              'Karen','Lucas','Marta','Nicolas','Olga','Pablo','Rocio','Sergio','Tamara','Ulises'])
           [1 + pg_temp.h('nom' || n) % 20],
       (ARRAY['Acosta','Benitez','Castro','Dominguez','Escobar','Ferreyra','Gimenez','Herrera',
              'Ibarra','Juarez','Ledesma','Molina','Navarro','Ojeda','Paz','Quiroga','Rojas',
              'Sosa','Torres','Vera'])[1 + pg_temp.h('ape' || n) % 20]
FROM generate_series(1, 300) AS n;

-- 2000 pedidos entre enero y octubre de 2026. Nacen PENDIENTE (regla R2 del TP2).
INSERT INTO pedido (fecha, forma_pago, cliente_id)
SELECT TIMESTAMPTZ '2026-01-01 09:00:00-03'
           + make_interval(mins => pg_temp.h('fecha' || n) % (300 * 24 * 60)),
       (ARRAY['EFECTIVO','TARJETA','TRANSFERENCIA'])[1 + pg_temp.h('pago' || n) % 3]::forma_pago,
       1 + pg_temp.h('cli' || n) % 300
FROM generate_series(1, 2000) AS n
ORDER BY n;

-- Entre 1 y 4 líneas por pedido. 17 es coprimo con 80: no repite producto en un pedido.
-- El precio de venta difiere del de lista (descuentos históricos de 0 a 10 %).
INSERT INTO detalle_pedido (id_pedido, id_producto, precio_unitario, cantidad)
SELECT p.id_pedido, pr.id_producto,
       round(pr.precio_lista * (90 + pg_temp.h('dto' || p.id_pedido || '-' || k) % 11) / 100.0, 2),
       1 + pg_temp.h('cant' || p.id_pedido || '-' || k) % 5
FROM pedido AS p
CROSS JOIN LATERAL generate_series(1, 1 + pg_temp.h('lineas' || p.id_pedido) % 4) AS k
JOIN producto AS pr
  ON pr.id_producto = 1 + (pg_temp.h('prod' || p.id_pedido) + k * 17) % 80
ORDER BY p.id_pedido, pr.id_producto;

-- Estados finales respetando las transiciones permitidas:
-- 10 % queda PENDIENTE, 10 % CANCELADO, 10 % CONFIRMADO y 70 % ENTREGADO.
UPDATE pedido SET estado = 'CANCELADO'  WHERE pg_temp.h('estado' || id_pedido) % 10 = 1;
UPDATE pedido SET estado = 'CONFIRMADO' WHERE pg_temp.h('estado' || id_pedido) % 10 >= 2;
UPDATE pedido SET estado = 'ENTREGADO'  WHERE pg_temp.h('estado' || id_pedido) % 10 >= 3;

-- Bajas lógicas posteriores a las ventas: se conserva la historia.
CALL tpi_baja_producto(7);
CALL tpi_baja_producto(23);
UPDATE categoria SET activo = FALSE WHERE nombre = 'Ensaladas';
