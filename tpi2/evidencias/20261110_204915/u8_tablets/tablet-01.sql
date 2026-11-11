BEGIN TRANSACTION;
CREATE TABLE cola_sync (
    solicitud_uuid TEXT PRIMARY KEY CHECK (length(solicitud_uuid) = 36),
    id_local       TEXT NOT NULL REFERENCES pedido_borrador (id_local),
    estado         TEXT NOT NULL DEFAULT 'PENDIENTE'
                   CHECK (estado IN ('PENDIENTE', 'APLICADO', 'CONFLICTO', 'RECHAZADO')),
    intentos       INTEGER NOT NULL DEFAULT 0 CHECK (intentos >= 0),
    creada_en      TEXT NOT NULL,
    ultimo_intento TEXT,
    ultimo_error   TEXT,
    respuesta      TEXT CHECK (respuesta IS NULL OR json_valid(respuesta)),
    id_pedido_servidor INTEGER
) STRICT;
INSERT INTO "cola_sync" VALUES('e0ac682d-aa9b-4b92-94ef-b7f571d66536','73fb2b82-7bd0-4ccd-8473-b2b548f09de9','CONFLICTO',2,'2026-11-10T23:50:14.823934Z','2026-11-10T23:50:17.276993Z',NULL,'{"estado": "CONFLICTO", "duplicada": false, "id_pedido": null, "problemas": [{"motivo": "PRECIO_CAMBIADO", "producto_id": 1, "precio_centavos_visto": 150000, "precio_centavos_actual": 165000}]}',NULL);
INSERT INTO "cola_sync" VALUES('48c8bf5e-6c64-4bb9-a0e2-c9fcc51dd817','a61e24d6-cb86-49d0-924a-197224a3b4b2','RECHAZADO',1,'2026-11-10T23:50:14.823934Z','2026-11-10T23:50:17.381420Z',NULL,'{"estado": "RECHAZADO", "duplicada": false, "id_pedido": null, "problemas": [{"motivo": "PRODUCTO_DADO_DE_BAJA", "producto_id": 2}]}',NULL);
INSERT INTO "cola_sync" VALUES('7a2d4dbe-63fc-440a-9cde-07ce37721b2c','760f1c90-0ca5-4939-b8c0-95eec5a2e882','APLICADO',1,'2026-11-10T23:50:14.825430Z','2026-11-10T23:50:17.489499Z',NULL,'{"estado": "APLICADO", "duplicada": false, "id_pedido": 3595, "problemas": []}',3595);
INSERT INTO "cola_sync" VALUES('472c607c-2465-422a-8532-8493a5b0ba50','71c97f6b-371f-4c36-8f0c-d36a1dcda6a3','RECHAZADO',1,'2026-11-10T23:50:14.826845Z','2026-11-10T23:50:17.793837Z',NULL,'{"estado": "RECHAZADO", "duplicada": false, "id_pedido": null, "problemas": [{"motivo": "STOCK_INSUFICIENTE", "pedido": 140, "producto_id": 5, "stock_actual": 139}]}',NULL);
INSERT INTO "cola_sync" VALUES('d949ca23-0eea-4018-a9d0-e8fd444bb2ee','73fb2b82-7bd0-4ccd-8473-b2b548f09de9','APLICADO',1,'2026-11-10T23:50:18.380633Z','2026-11-10T23:50:18.381406Z',NULL,'{"estado": "APLICADO", "duplicada": false, "id_pedido": 3596, "problemas": []}',3596);
INSERT INTO "cola_sync" VALUES('fd48f0f6-6662-4d01-9621-b8f41a9f1cb1','9ccdd9fe-e8f2-4588-96c4-97bd8fd5bd36','APLICADO',2,'2026-11-10T23:50:18.930103Z','2026-11-10T23:50:19.446253Z',NULL,'{"estado": "APLICADO", "duplicada": true, "id_pedido": 3597, "problemas": []}',3597);
INSERT INTO "cola_sync" VALUES('82fb3e38-3fa5-4096-86c4-5f0d7f36ad4f','59a7773d-d15a-4a5b-9447-5b225bfe2df6','APLICADO',1,'2026-11-10T23:50:20.220908Z','2026-11-10T23:50:20.225246Z',NULL,'{"estado": "APLICADO", "duplicada": false, "id_pedido": 3598, "problemas": []}',3598);
CREATE TABLE item_borrador (
    id_local              TEXT NOT NULL REFERENCES pedido_borrador (id_local),
    producto_id           INTEGER NOT NULL REFERENCES producto_cache (id),
    cantidad              INTEGER NOT NULL CHECK (cantidad > 0),
    precio_centavos_visto INTEGER NOT NULL CHECK (precio_centavos_visto >= 0),
    PRIMARY KEY (id_local, producto_id)
) STRICT;
INSERT INTO "item_borrador" VALUES('73fb2b82-7bd0-4ccd-8473-b2b548f09de9',1,1,165000);
INSERT INTO "item_borrador" VALUES('a61e24d6-cb86-49d0-924a-197224a3b4b2',2,1,415000);
INSERT INTO "item_borrador" VALUES('760f1c90-0ca5-4939-b8c0-95eec5a2e882',3,2,180000);
INSERT INTO "item_borrador" VALUES('71c97f6b-371f-4c36-8f0c-d36a1dcda6a3',5,140,175000);
INSERT INTO "item_borrador" VALUES('9ccdd9fe-e8f2-4588-96c4-97bd8fd5bd36',3,1,180000);
INSERT INTO "item_borrador" VALUES('59a7773d-d15a-4a5b-9447-5b225bfe2df6',4,2,410000);
CREATE TABLE pedido_borrador (
    id_local      TEXT PRIMARY KEY CHECK (length(id_local) = 36 AND id_local GLOB
        '[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-*'),
    forma_pago    TEXT NOT NULL CHECK (forma_pago IN ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA')),
    creado_en     TEXT NOT NULL,
    estado        TEXT NOT NULL DEFAULT 'BORRADOR'
                  CHECK (estado IN ('BORRADOR', 'ENVIADO', 'CONFIRMADO', 'CONFLICTO', 'RECHAZADO')),
    id_pedido_servidor INTEGER,
    CHECK ((estado = 'CONFIRMADO') = (id_pedido_servidor IS NOT NULL))
) STRICT;
INSERT INTO "pedido_borrador" VALUES('73fb2b82-7bd0-4ccd-8473-b2b548f09de9','EFECTIVO','2026-11-10T23:50:14.290829Z','CONFIRMADO',3596);
INSERT INTO "pedido_borrador" VALUES('a61e24d6-cb86-49d0-924a-197224a3b4b2','TARJETA','2026-11-10T23:50:14.292237Z','RECHAZADO',NULL);
INSERT INTO "pedido_borrador" VALUES('760f1c90-0ca5-4939-b8c0-95eec5a2e882','TRANSFERENCIA','2026-11-10T23:50:14.293242Z','CONFIRMADO',3595);
INSERT INTO "pedido_borrador" VALUES('71c97f6b-371f-4c36-8f0c-d36a1dcda6a3','EFECTIVO','2026-11-10T23:50:14.293242Z','RECHAZADO',NULL);
INSERT INTO "pedido_borrador" VALUES('9ccdd9fe-e8f2-4588-96c4-97bd8fd5bd36','EFECTIVO','2026-11-10T23:50:18.929101Z','CONFIRMADO',3597);
INSERT INTO "pedido_borrador" VALUES('59a7773d-d15a-4a5b-9447-5b225bfe2df6','EFECTIVO','2026-11-10T23:50:20.219903Z','CONFIRMADO',3598);
CREATE TABLE producto_cache (
    id               INTEGER PRIMARY KEY,
    nombre           TEXT NOT NULL,
    categoria        TEXT NOT NULL,
    precio_centavos  INTEGER NOT NULL CHECK (precio_centavos >= 0),
    stock_visto      INTEGER NOT NULL CHECK (stock_visto >= 0),
    disponible       INTEGER NOT NULL CHECK (disponible IN (0, 1)),
    eliminado        INTEGER NOT NULL CHECK (eliminado IN (0, 1)),
    version_snapshot INTEGER NOT NULL REFERENCES snapshot (version)
) STRICT;
INSERT INTO "producto_cache" VALUES(1,'Pizza variedad 01','Pizzas',165000,327,1,0,3);
INSERT INTO "producto_cache" VALUES(2,'Pizza variedad 02','Pizzas',415000,172,0,1,3);
INSERT INTO "producto_cache" VALUES(3,'Pizza variedad 03','Pizzas',180000,255,1,0,3);
INSERT INTO "producto_cache" VALUES(4,'Pizza variedad 04','Pizzas',410000,3,1,0,3);
INSERT INTO "producto_cache" VALUES(5,'Pizza variedad 05','Pizzas',175000,139,1,0,3);
INSERT INTO "producto_cache" VALUES(6,'Pizza variedad 06','Pizzas',255000,102,1,0,3);
INSERT INTO "producto_cache" VALUES(7,'Pizza variedad 07','Pizzas',365000,265,0,1,3);
INSERT INTO "producto_cache" VALUES(8,'Pizza variedad 08','Pizzas',270000,485,1,0,3);
INSERT INTO "producto_cache" VALUES(9,'Pizza variedad 09','Pizzas',265000,296,1,0,3);
INSERT INTO "producto_cache" VALUES(10,'Pizza variedad 10','Pizzas',85000,356,1,0,3);
INSERT INTO "producto_cache" VALUES(11,'Empanada variedad 01','Empanadas',120000,305,1,0,3);
INSERT INTO "producto_cache" VALUES(12,'Empanada variedad 02','Empanadas',395000,374,1,0,3);
INSERT INTO "producto_cache" VALUES(13,'Empanada variedad 03','Empanadas',320000,359,1,0,3);
INSERT INTO "producto_cache" VALUES(14,'Empanada variedad 04','Empanadas',190000,293,1,0,3);
INSERT INTO "producto_cache" VALUES(15,'Empanada variedad 05','Empanadas',165000,464,1,0,3);
INSERT INTO "producto_cache" VALUES(16,'Empanada variedad 06','Empanadas',210000,253,1,0,3);
INSERT INTO "producto_cache" VALUES(17,'Empanada variedad 07','Empanadas',340000,459,1,0,3);
INSERT INTO "producto_cache" VALUES(18,'Empanada variedad 08','Empanadas',410000,408,1,0,3);
INSERT INTO "producto_cache" VALUES(19,'Empanada variedad 09','Empanadas',405000,451,1,0,3);
INSERT INTO "producto_cache" VALUES(20,'Empanada variedad 10','Empanadas',365000,499,1,0,3);
INSERT INTO "producto_cache" VALUES(21,'Hamburguesa variedad 01','Hamburguesas',445000,462,1,0,3);
INSERT INTO "producto_cache" VALUES(22,'Hamburguesa variedad 02','Hamburguesas',210000,147,1,0,3);
INSERT INTO "producto_cache" VALUES(23,'Hamburguesa variedad 03','Hamburguesas',430000,163,0,1,3);
INSERT INTO "producto_cache" VALUES(24,'Hamburguesa variedad 04','Hamburguesas',115000,337,1,0,3);
INSERT INTO "producto_cache" VALUES(25,'Hamburguesa variedad 05','Hamburguesas',240000,239,1,0,3);
INSERT INTO "producto_cache" VALUES(26,'Hamburguesa variedad 06','Hamburguesas',175000,386,1,0,3);
INSERT INTO "producto_cache" VALUES(27,'Hamburguesa variedad 07','Hamburguesas',160000,271,1,0,3);
INSERT INTO "producto_cache" VALUES(28,'Hamburguesa variedad 08','Hamburguesas',275000,196,1,0,3);
INSERT INTO "producto_cache" VALUES(29,'Hamburguesa variedad 09','Hamburguesas',120000,113,1,0,3);
INSERT INTO "producto_cache" VALUES(30,'Hamburguesa variedad 10','Hamburguesas',320000,278,1,0,3);
INSERT INTO "producto_cache" VALUES(31,'Bebida variedad 01','Bebidas',270000,259,1,0,3);
INSERT INTO "producto_cache" VALUES(32,'Bebida variedad 02','Bebidas',100000,371,1,0,3);
INSERT INTO "producto_cache" VALUES(33,'Bebida variedad 03','Bebidas',230000,162,1,0,3);
INSERT INTO "producto_cache" VALUES(34,'Bebida variedad 04','Bebidas',110000,432,1,0,3);
INSERT INTO "producto_cache" VALUES(35,'Bebida variedad 05','Bebidas',235000,231,1,0,3);
INSERT INTO "producto_cache" VALUES(36,'Bebida variedad 06','Bebidas',165000,309,1,0,3);
INSERT INTO "producto_cache" VALUES(37,'Bebida variedad 07','Bebidas',355000,443,1,0,3);
INSERT INTO "producto_cache" VALUES(38,'Bebida variedad 08','Bebidas',365000,481,1,0,3);
INSERT INTO "producto_cache" VALUES(39,'Bebida variedad 09','Bebidas',350000,339,1,0,3);
INSERT INTO "producto_cache" VALUES(40,'Bebida variedad 10','Bebidas',320000,145,1,0,3);
INSERT INTO "producto_cache" VALUES(41,'Postre variedad 01','Postres',375000,263,1,0,3);
INSERT INTO "producto_cache" VALUES(42,'Postre variedad 02','Postres',245000,236,1,0,3);
INSERT INTO "producto_cache" VALUES(43,'Postre variedad 03','Postres',165000,462,1,0,3);
INSERT INTO "producto_cache" VALUES(44,'Postre variedad 04','Postres',165000,375,1,0,3);
INSERT INTO "producto_cache" VALUES(45,'Postre variedad 05','Postres',300000,105,1,0,3);
INSERT INTO "producto_cache" VALUES(46,'Postre variedad 06','Postres',220000,134,1,0,3);
INSERT INTO "producto_cache" VALUES(47,'Postre variedad 07','Postres',110000,359,1,0,3);
INSERT INTO "producto_cache" VALUES(48,'Postre variedad 08','Postres',85000,316,1,0,3);
INSERT INTO "producto_cache" VALUES(49,'Postre variedad 09','Postres',90000,438,1,0,3);
INSERT INTO "producto_cache" VALUES(50,'Postre variedad 10','Postres',210000,498,1,0,3);
INSERT INTO "producto_cache" VALUES(51,'Ensalada variedad 01','Ensaladas',120000,424,0,0,3);
INSERT INTO "producto_cache" VALUES(52,'Ensalada variedad 02','Ensaladas',375000,328,0,0,3);
INSERT INTO "producto_cache" VALUES(53,'Ensalada variedad 03','Ensaladas',390000,103,0,0,3);
INSERT INTO "producto_cache" VALUES(54,'Ensalada variedad 04','Ensaladas',185000,233,0,0,3);
INSERT INTO "producto_cache" VALUES(55,'Ensalada variedad 05','Ensaladas',265000,152,0,0,3);
INSERT INTO "producto_cache" VALUES(56,'Ensalada variedad 06','Ensaladas',435000,362,0,0,3);
INSERT INTO "producto_cache" VALUES(57,'Ensalada variedad 07','Ensaladas',345000,490,0,0,3);
INSERT INTO "producto_cache" VALUES(58,'Ensalada variedad 08','Ensaladas',210000,189,0,0,3);
INSERT INTO "producto_cache" VALUES(59,'Ensalada variedad 09','Ensaladas',265000,196,0,0,3);
INSERT INTO "producto_cache" VALUES(60,'Ensalada variedad 10','Ensaladas',395000,299,0,0,3);
INSERT INTO "producto_cache" VALUES(61,'Pasta variedad 01','Pastas',150000,406,1,0,3);
INSERT INTO "producto_cache" VALUES(62,'Pasta variedad 02','Pastas',155000,463,1,0,3);
INSERT INTO "producto_cache" VALUES(63,'Pasta variedad 03','Pastas',475000,374,1,0,3);
INSERT INTO "producto_cache" VALUES(64,'Pasta variedad 04','Pastas',430000,411,1,0,3);
INSERT INTO "producto_cache" VALUES(65,'Pasta variedad 05','Pastas',185000,442,1,0,3);
INSERT INTO "producto_cache" VALUES(66,'Pasta variedad 06','Pastas',345000,321,1,0,3);
INSERT INTO "producto_cache" VALUES(67,'Pasta variedad 07','Pastas',290000,390,1,0,3);
INSERT INTO "producto_cache" VALUES(68,'Pasta variedad 08','Pastas',375000,254,1,0,3);
INSERT INTO "producto_cache" VALUES(69,'Pasta variedad 09','Pastas',380000,304,1,0,3);
INSERT INTO "producto_cache" VALUES(70,'Pasta variedad 10','Pastas',115000,381,1,0,3);
INSERT INTO "producto_cache" VALUES(71,'Sandwich variedad 01','Sandwiches',415000,256,1,0,3);
INSERT INTO "producto_cache" VALUES(72,'Sandwich variedad 02','Sandwiches',325000,385,1,0,3);
INSERT INTO "producto_cache" VALUES(73,'Sandwich variedad 03','Sandwiches',395000,239,1,0,3);
INSERT INTO "producto_cache" VALUES(74,'Sandwich variedad 04','Sandwiches',325000,425,1,0,3);
INSERT INTO "producto_cache" VALUES(75,'Sandwich variedad 05','Sandwiches',295000,238,1,0,3);
INSERT INTO "producto_cache" VALUES(76,'Sandwich variedad 06','Sandwiches',105000,324,1,0,3);
INSERT INTO "producto_cache" VALUES(77,'Sandwich variedad 07','Sandwiches',475000,460,1,0,3);
INSERT INTO "producto_cache" VALUES(78,'Sandwich variedad 08','Sandwiches',160000,381,1,0,3);
INSERT INTO "producto_cache" VALUES(79,'Sandwich variedad 09','Sandwiches',230000,267,1,0,3);
INSERT INTO "producto_cache" VALUES(80,'Sandwich variedad 10','Sandwiches',375000,161,1,0,3);
INSERT INTO "producto_cache" VALUES(141,'Minuta clasica 01','Minutas',180000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(142,'Minuta clasica 02','Minutas',215000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(143,'Minuta clasica 03','Minutas',60000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(144,'Minuta clasica 04','Minutas',235000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(145,'Minuta clasica 05','Minutas',190000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(146,'Minuta clasica 06','Minutas',75000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(147,'Minuta clasica 07','Minutas',120000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(148,'Minuta clasica 08','Minutas',65000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(149,'Minuta clasica 09','Minutas',170000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(150,'Minuta clasica 10','Minutas',135000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(151,'Pizza al molde 01','Pizzas',55000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(152,'Pizza al molde 02','Pizzas',55000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(153,'Pizza al molde 03','Pizzas',245000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(154,'Pizza al molde 04','Pizzas',125000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(155,'Pizza al molde 05','Pizzas',240000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(156,'Pizza al molde 06','Pizzas',220000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(157,'Pizza al molde 07','Pizzas',155000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(158,'Pizza al molde 08','Pizzas',120000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(159,'Pizza al molde 09','Pizzas',75000,0,0,1,3);
INSERT INTO "producto_cache" VALUES(160,'Pizza al molde 10','Pizzas',160000,0,0,1,3);
CREATE TABLE snapshot (
    version       INTEGER PRIMARY KEY,
    servidor_en   TEXT NOT NULL,                  -- hora del servidor al generar la copia
    descargado_en TEXT NOT NULL,
    productos     INTEGER NOT NULL CHECK (productos > 0)
) STRICT;
INSERT INTO "snapshot" VALUES(1,'2026-11-10T23:50:11.884Z','2026-11-10T23:50:11.890359Z',100);
INSERT INTO "snapshot" VALUES(2,'2026-11-10T23:50:18.371Z','2026-11-10T23:50:18.377173Z',100);
INSERT INTO "snapshot" VALUES(3,'2026-11-10T23:50:20.108Z','2026-11-10T23:50:20.114719Z',100);
CREATE UNIQUE INDEX uq_cola_un_pendiente_por_borrador ON cola_sync (id_local) WHERE estado = 'PENDIENTE';
CREATE INDEX idx_producto_catalogo ON producto_cache (disponible, eliminado, categoria, nombre);
CREATE TRIGGER trg_cola_borrador_con_items
BEFORE INSERT ON cola_sync
WHEN NOT EXISTS (SELECT 1 FROM item_borrador WHERE id_local = NEW.id_local)
BEGIN
    SELECT RAISE(ABORT, 'El borrador no tiene ítems: no se puede enviar');
END;
CREATE TRIGGER trg_items_inmutables_tras_envio_ins
BEFORE INSERT ON item_borrador
WHEN EXISTS (SELECT 1 FROM cola_sync WHERE id_local = NEW.id_local AND estado IN ('PENDIENTE', 'APLICADO'))
BEGIN
    SELECT RAISE(ABORT, 'El borrador ya fue enviado: no se puede modificar');
END;
CREATE TRIGGER trg_items_inmutables_tras_envio_upd
BEFORE UPDATE ON item_borrador
WHEN EXISTS (SELECT 1 FROM cola_sync WHERE id_local = OLD.id_local AND estado IN ('PENDIENTE', 'APLICADO'))
BEGIN
    SELECT RAISE(ABORT, 'El borrador ya fue enviado: no se puede modificar');
END;
CREATE TRIGGER trg_cola_resuelta_inmutable
BEFORE UPDATE OF estado, respuesta ON cola_sync
WHEN OLD.estado <> 'PENDIENTE'
BEGIN
    SELECT RAISE(ABORT, 'La solicitud ya fue resuelta por el servidor');
END;
CREATE VIEW v_catalogo AS
SELECT id, nombre, categoria, precio_centavos, stock_visto
FROM producto_cache
WHERE disponible = 1 AND eliminado = 0
ORDER BY categoria, nombre;
COMMIT;
