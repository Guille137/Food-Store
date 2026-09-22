-- Ejecutar una sola vez sobre una copia con el seed y los triggers del TP2.
-- El ejecutor administra BEGIN/ROLLBACK/COMMIT y el respaldo previo.
-- Los ids se obtienen con RETURNING: no se suponen valores de secuencias.
CREATE TEMP TABLE tp3_productos (n INTEGER PRIMARY KEY, id INTEGER UNIQUE) ON COMMIT DROP;
CREATE TEMP TABLE tp3_clientes (n INTEGER PRIMARY KEY, id INTEGER UNIQUE) ON COMMIT DROP;
CREATE TEMP TABLE tp3_pedidos (n INTEGER PRIMARY KEY, id INTEGER UNIQUE) ON COMMIT DROP;

WITH categorias AS (
  SELECT id_categoria, row_number() OVER (ORDER BY id_categoria) AS n,
         count(*) OVER () AS total
  FROM categoria WHERE activo = TRUE
), nuevos AS (
  INSERT INTO producto (nombre, precio_lista, stock, activo, categoria_id)
  SELECT 'TP3 Producto ' || lpad(g::text, 5, '0'),
         500 + (g * 37 % 4501), 1 + (g * 17 % 200), TRUE, c.id_categoria
  FROM generate_series(1, 50000) AS s(g)
  JOIN categorias c ON c.n = 1 + (g-1) % c.total
  ORDER BY g
  RETURNING id_producto, nombre
)
INSERT INTO tp3_productos SELECT right(nombre, 5)::integer, id_producto FROM nuevos;

WITH nuevos AS (
  INSERT INTO cliente (correo_electronico, nombre, apellido)
  SELECT 'tp3_' || g || '@example.test', 'Cliente ' || g, 'Prueba'
  FROM generate_series(1, 20000) AS s(g) ORDER BY g
  RETURNING id_cliente, correo_electronico
)
INSERT INTO tp3_clientes
SELECT split_part(split_part(correo_electronico, '@', 1), '_', 2)::integer, id_cliente
FROM nuevos;

-- Las fechas se distribuyen de forma determinista durante 2025.
WITH nuevos AS (
  INSERT INTO pedido (fecha, estado, forma_pago, cliente_id)
  SELECT TIMESTAMPTZ '2025-01-01 00:00:00+00'
           + ((g*13 % 365) * INTERVAL '1 day') + (g * INTERVAL '1 second'),
         'PENDIENTE',
         (ARRAY['EFECTIVO','TARJETA','TRANSFERENCIA'])[1 + g%3]::forma_pago,
         c.id
  FROM generate_series(1, 200000) AS s(g)
  JOIN tp3_clientes c ON c.n = 1 + (g-1)%20000
  ORDER BY g
  RETURNING id_pedido
)
-- En esta copia sin otras escrituras, el orden de ids conserva el orden de generación.
INSERT INTO tp3_pedidos SELECT row_number() OVER (ORDER BY id_pedido)::integer, id_pedido FROM nuevos;

INSERT INTO detalle_pedido (id_pedido, id_producto, precio_unitario, cantidad)
SELECT o.id, m.id, p.precio_lista, 1
FROM tp3_pedidos o
CROSS JOIN generate_series(0,2) AS s(linea)
JOIN tp3_productos m ON m.n = 1 + ((o.n*7 + s.linea*101) % 50000)
JOIN producto p ON p.id_producto=m.id
ORDER BY o.id, m.id;

-- Transiciones válidas: primero confirmar; luego entregar. Otras filas se cancelan.
UPDATE pedido p SET estado='CONFIRMADO'
FROM tp3_pedidos t WHERE p.id_pedido=t.id AND t.n%4 IN (1,2);
UPDATE pedido p SET estado='ENTREGADO'
FROM tp3_pedidos t WHERE p.id_pedido=t.id AND t.n%4=2;
UPDATE pedido p SET estado='CANCELADO'
FROM tp3_pedidos t WHERE p.id_pedido=t.id AND t.n%4=3;

-- Baja posterior a las ventas: preserva las líneas históricas.
UPDATE producto p SET activo=FALSE
FROM tp3_productos t WHERE p.id_producto=t.id AND t.n%10=0;

SELECT 'productos_generados' AS control, count(*) AS filas FROM tp3_productos
UNION ALL SELECT 'clientes_generados', count(*) FROM tp3_clientes
UNION ALL SELECT 'pedidos_generados', count(*) FROM tp3_pedidos;
