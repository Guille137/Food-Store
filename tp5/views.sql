-- V1: catálogo vigente. Una baja de categoría también oculta sus productos.
CREATE VIEW tp5_productos_vigentes
    (id_producto, nombre_producto, precio_lista, stock, id_categoria, nombre_categoria)
AS
SELECT p.id_producto, p.nombre, p.precio_lista, p.stock, c.id_categoria, c.nombre
FROM producto p JOIN categoria c ON c.id_categoria = p.categoria_id
WHERE p.activo AND c.activo;
