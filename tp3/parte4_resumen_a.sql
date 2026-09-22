SELECT c.id_categoria, c.nombre, count(p.id_producto) AS cantidad_productos
FROM categoria c
LEFT JOIN producto p ON p.categoria_id=c.id_categoria AND p.activo=TRUE
WHERE c.activo=TRUE
GROUP BY c.id_categoria, c.nombre
ORDER BY cantidad_productos DESC, c.id_categoria ASC;
