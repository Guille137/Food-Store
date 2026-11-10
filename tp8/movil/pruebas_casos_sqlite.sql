-- Escenarios reproducibles del semáforo sobre datos sintéticos locales.
-- Para demostrar C2/C4 en PostgreSQL, usar además las instrucciones del README:
-- aquí se simulan snapshots nuevos en SQLite, sin escribir en el servidor.
.bail off
.headers on
.mode column
PRAGMA foreign_keys = ON;

DELETE FROM cola_sync;
DELETE FROM item_borrador;
DELETE FROM pedido_borrador;
DELETE FROM producto_cache;
DELETE FROM snapshot_servidor;
INSERT INTO producto_cache VALUES
  (1, 'Muzzarella de prueba', 100000, 10, 1, 0, '2026-11-10T12:00:00-03:00'),
  (2, 'Bebida inactiva de prueba', 80000, 10, 0, 1, '2026-11-10T12:00:00-03:00'),
  (3, 'Bebida activa de prueba', 90000, 5, 1, 0, '2026-11-10T12:00:00-03:00');
INSERT INTO snapshot_servidor VALUES
  (1, 'Muzzarella de prueba', 100000, 10, 't', 'f'),
  (2, 'Bebida inactiva de prueba', 80000, 10, 'f', 't'),
  (3, 'Bebida activa de prueba', 90000, 5, 't', 'f');

-- C2: cambiar precio en el snapshot -> conflicto; aceptar el nuevo precio
-- y crear UUID distinto -> nueva solicitud simulada aprobada.
INSERT INTO pedido_borrador VALUES ('60000000-0000-4000-8000-000000000002', 'usuario-prueba', 'EFECTIVO', '2026-11-10T12:10:00-03:00');
INSERT INTO item_borrador VALUES ('60000000-0000-4000-8000-000000000002', 1, 1, 100000);
INSERT INTO cola_sync VALUES ('80000000-0000-4000-8000-000000000201', '60000000-0000-4000-8000-000000000002', 'PENDIENTE', NULL);
UPDATE snapshot_servidor SET precio_centavos=110000 WHERE id=1;
.read cargar_cache.sql
.read semaforo.sql
SELECT 'C2 conflicto esperado' AS caso, estado, motivo FROM cola_sync WHERE solicitud_uuid='80000000-0000-4000-8000-000000000201';
UPDATE item_borrador SET precio_centavos_visto=110000 WHERE id_local='60000000-0000-4000-8000-000000000002';
INSERT INTO cola_sync VALUES ('80000000-0000-4000-8000-000000000202', '60000000-0000-4000-8000-000000000002', 'PENDIENTE', NULL);
.read semaforo.sql
SELECT 'C2 aceptación esperada' AS caso, estado, motivo FROM cola_sync WHERE solicitud_uuid='80000000-0000-4000-8000-000000000202';

-- C3: la cantidad supera el stock de la instantánea.
INSERT INTO pedido_borrador VALUES ('60000000-0000-4000-8000-000000000003', 'usuario-prueba', 'TARJETA', '2026-11-10T12:11:00-03:00');
INSERT INTO item_borrador VALUES ('60000000-0000-4000-8000-000000000003', 1, 11, 110000);
INSERT INTO cola_sync VALUES ('80000000-0000-4000-8000-000000000203', '60000000-0000-4000-8000-000000000003', 'PENDIENTE', NULL);
.read semaforo.sql
SELECT 'C3 rechazo esperado' AS caso, estado, motivo FROM cola_sync WHERE solicitud_uuid='80000000-0000-4000-8000-000000000203';

-- C4: nueva instantánea conserva el producto como lápida, fuera de catálogo.
INSERT INTO pedido_borrador VALUES ('60000000-0000-4000-8000-000000000004', 'usuario-prueba', 'TRANSFERENCIA', '2026-11-10T12:12:00-03:00');
INSERT INTO item_borrador VALUES ('60000000-0000-4000-8000-000000000004', 1, 1, 110000);
INSERT INTO cola_sync VALUES ('80000000-0000-4000-8000-000000000204', '60000000-0000-4000-8000-000000000004', 'PENDIENTE', NULL);
UPDATE snapshot_servidor SET disponible='f', eliminado='t' WHERE id=1;
.read cargar_cache.sql
.read semaforo.sql
SELECT 'C4 rechazo esperado' AS caso, estado, motivo FROM cola_sync WHERE solicitud_uuid='80000000-0000-4000-8000-000000000204';
SELECT 'C4 lápida conservada' AS comprobacion, id, disponible, eliminado FROM snapshot_servidor WHERE id=1;
SELECT 'C4 producto oculto del catálogo, fila local conservada' AS comprobacion,
       count(*) AS filas_visibles
FROM producto_cache WHERE id=1 AND disponible=1 AND eliminado=0;

-- C5: todos los datos coinciden; esto no crea una venta.
INSERT INTO pedido_borrador VALUES ('60000000-0000-4000-8000-000000000005', 'usuario-prueba', 'EFECTIVO', '2026-11-10T12:13:00-03:00');
INSERT INTO item_borrador VALUES ('60000000-0000-4000-8000-000000000005', 3, 2, 90000);
INSERT INTO cola_sync VALUES ('80000000-0000-4000-8000-000000000205', '60000000-0000-4000-8000-000000000005', 'PENDIENTE', NULL);
.read semaforo.sql
SELECT 'C5 aprobación simulada esperada' AS caso, estado, motivo FROM cola_sync WHERE solicitud_uuid='80000000-0000-4000-8000-000000000205';

-- C6: UUID repetido debe fallar por PK; la solicitud ya resuelta no se reevalúa.
INSERT INTO pedido_borrador VALUES ('60000000-0000-4000-8000-000000000006', 'usuario-prueba', 'TARJETA', '2026-11-10T12:14:00-03:00');
INSERT INTO item_borrador VALUES ('60000000-0000-4000-8000-000000000006', 3, 1, 90000);
INSERT INTO cola_sync VALUES ('80000000-0000-4000-8000-000000000206', '60000000-0000-4000-8000-000000000006', 'PENDIENTE', NULL);
.read semaforo.sql
INSERT INTO cola_sync VALUES ('80000000-0000-4000-8000-000000000206', '60000000-0000-4000-8000-000000000006', 'PENDIENTE', NULL);
.read semaforo.sql
SELECT 'C6 una única solicitud' AS comprobacion, count(*) AS filas,
       min(estado) AS estado FROM cola_sync WHERE solicitud_uuid='80000000-0000-4000-8000-000000000206';

SELECT 'Conteos locales por estado' AS resumen, estado, count(*) AS solicitudes
FROM cola_sync GROUP BY estado ORDER BY estado;
