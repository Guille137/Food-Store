-- Ejemplo de la Parte 5: categoría 1, precio de 1000 a 1500 inclusive,
-- productos activos y las primeras 50 filas ordenadas por precio e id.
SELECT id_producto, nombre, precio_lista
FROM producto
WHERE activo=TRUE AND categoria_id=1 AND precio_lista BETWEEN 1000 AND 1500
ORDER BY precio_lista ASC, id_producto ASC
LIMIT 50;
