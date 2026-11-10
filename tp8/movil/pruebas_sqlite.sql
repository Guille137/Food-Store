-- Ejecutar desde la carpeta tp8/movil con sqlite3 foodstore_movil.db < pruebas_sqlite.sql
.bail off
.headers on
.mode column
PRAGMA foreign_keys = ON;

-- Preparación local reproducible. No contiene datos personales reales.
DELETE FROM cola_sync;
DELETE FROM item_borrador;
DELETE FROM pedido_borrador;
DELETE FROM producto_cache;
INSERT INTO producto_cache VALUES
  (1, 'Muzzarella de prueba', 100000, 10, 1, 0, '2026-11-10T12:00:00-03:00'),
  (2, 'Bebida activa de prueba', 90000, 5, 1, 0, '2026-11-10T12:00:00-03:00');

-- 1) Borrador completo guardado atómicamente.
BEGIN;
INSERT INTO pedido_borrador VALUES ('60000000-0000-4000-8000-000000000005', 'usuario-prueba', 'EFECTIVO', '2026-11-10T12:01:00-03:00');
INSERT INTO item_borrador VALUES ('60000000-0000-4000-8000-000000000005', 1, 2, 100000);
INSERT INTO cola_sync VALUES ('80000000-0000-4000-8000-000000000005', '60000000-0000-4000-8000-000000000005', 'PENDIENTE', NULL);
COMMIT;
SELECT 'COMMIT: borrador, ítem y solicitud' AS comprobacion,
       (SELECT count(*) FROM pedido_borrador WHERE id_local='60000000-0000-4000-8000-000000000005') AS borradores,
       (SELECT count(*) FROM item_borrador WHERE id_local='60000000-0000-4000-8000-000000000005') AS items,
       (SELECT count(*) FROM cola_sync WHERE solicitud_uuid='80000000-0000-4000-8000-000000000005') AS solicitudes;

-- Operación de ejemplo deshecha; el conteo final debe ser cero.
BEGIN;
INSERT INTO pedido_borrador VALUES ('60000000-0000-4000-8000-000000000009', 'usuario-prueba', 'TARJETA', '2026-11-10T12:02:00-03:00');
ROLLBACK;
SELECT 'ROLLBACK: filas esperadas 0' AS comprobacion,
       (SELECT count(*) FROM pedido_borrador WHERE id_local='60000000-0000-4000-8000-000000000009') AS filas;

-- C1: catálogo disponible consultable sin conexión.
SELECT id, nombre, precio_centavos, stock_visto
FROM producto_cache WHERE disponible=1 AND eliminado=0 ORDER BY id;

-- C7: los dos INSERT inválidos se esperan fallidos. SAVEPOINT permite seguir
-- con el script en SQLite CLI y medir que no quedó ningún ítem nuevo.
SAVEPOINT prueba_c7_cantidad;
INSERT INTO item_borrador VALUES ('60000000-0000-4000-8000-000000000005', 2, 0, 90000);
ROLLBACK TO prueba_c7_cantidad;
RELEASE prueba_c7_cantidad;
SAVEPOINT prueba_c7_producto;
INSERT INTO item_borrador VALUES ('60000000-0000-4000-8000-000000000005', 999999, 1, 1);
ROLLBACK TO prueba_c7_producto;
RELEASE prueba_c7_producto;
SELECT 'C7: no quedaron filas inválidas' AS comprobacion,
       (SELECT count(*) FROM item_borrador WHERE id_local='60000000-0000-4000-8000-000000000005') AS items_validos;
