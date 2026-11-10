-- Ejecutar sobre una copia de pruebas de Food Store.
-- Los productos inactivos se conservan como lápidas para que SQLite pueda
-- rechazar borradores viejos; no se exportan datos de clientes.
CREATE OR REPLACE VIEW v_snapshot_movil AS
SELECT
    p.id_producto AS id,
    p.nombre,
    (p.precio_lista * 100)::bigint AS precio_centavos,
   CASE WHEN p.activo AND c.activo THEN 't' ELSE 'f' END AS disponible,
   CASE WHEN NOT p.activo THEN 't' ELSE 'f' END AS eliminado
FROM producto AS p
JOIN categoria AS c ON c.id_categoria = p.categoria_id;

-- Exportar desde psql:
-- \copy (SELECT * FROM v_snapshot_movil ORDER BY id) TO 'tp8/movil/servidor_snapshot.csv' CSV HEADER
-- El precio se convierte a centavos enteros y nunca se exportan pedidos/clientes.

SELECT * FROM v_snapshot_movil ORDER BY id;

