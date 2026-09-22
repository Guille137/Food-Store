SELECT c.id_categoria, c.nombre, coalesce(t.cantidad_productos,0) AS cantidad_productos
FROM categoria c
LEFT JOIN (
  SELECT categoria_id, count(*) AS cantidad_productos
  FROM producto WHERE activo=TRUE GROUP BY categoria_id
) t ON t.categoria_id=c.id_categoria
WHERE c.activo=TRUE
ORDER BY cantidad_productos DESC, c.id_categoria ASC;
