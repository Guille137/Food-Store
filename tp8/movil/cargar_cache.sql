-- Ejecutar después de importar la instantánea nueva a snapshot_servidor.
-- Conserva las filas que desaparecieron del servidor como lápidas locales,
-- para que los borradores antiguos mantengan sus claves foráneas.
BEGIN IMMEDIATE;

UPDATE producto_cache
SET disponible = 0,
    eliminado = 1,
    fecha_copia = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id NOT IN (SELECT id FROM snapshot_servidor);

INSERT INTO producto_cache
    (id, nombre, precio_centavos, stock_visto, disponible, eliminado, fecha_copia)
SELECT id, nombre, precio_centavos, stock,
       CASE WHEN disponible = 't' THEN 1 ELSE 0 END,
       CASE WHEN eliminado = 't' THEN 1 ELSE 0 END,
       strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM snapshot_servidor
WHERE 1
ON CONFLICT(id) DO UPDATE SET
    nombre = excluded.nombre,
    precio_centavos = excluded.precio_centavos,
    stock_visto = excluded.stock_visto,
    disponible = excluded.disponible,
    eliminado = excluded.eliminado,
    fecha_copia = excluded.fecha_copia;

COMMIT;
