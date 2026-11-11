-- Unidad 8 · Base local SQLite de la tablet de feria.
-- Spec: .kiro/specs/u8-sqlite-sincronizacion/. Evoluciona el esquema de tp8/movil
-- e incorpora las correcciones de la revisión de código de esa entrega:
--   R1 una solicitud sin ítems ya no puede encolarse (antes quedaba aprobada);
--   R2 un borrador no puede tener dos solicitudes PENDIENTE a la vez;
--   R3 una instantánea vacía no puede reemplazar el catálogo (antes marcaba todo como baja).
-- Requiere SQLite 3.37+ (tablas STRICT). Se ejecuta una vez al crear la base local.
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;          -- lecturas del catálogo sin bloquear la sincronización

-- Cada descarga del catálogo queda registrada. R3: nunca con cero productos.
CREATE TABLE snapshot (
    version       INTEGER PRIMARY KEY,
    servidor_en   TEXT NOT NULL,                  -- hora del servidor al generar la copia
    descargado_en TEXT NOT NULL,
    productos     INTEGER NOT NULL CHECK (productos > 0)
) STRICT;

-- Copia local del catálogo. Los productos dados de baja se conservan como
-- lápidas (eliminado = 1) para que los borradores viejos mantengan su FK.
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

CREATE TABLE item_borrador (
    id_local              TEXT NOT NULL REFERENCES pedido_borrador (id_local),
    producto_id           INTEGER NOT NULL REFERENCES producto_cache (id),
    cantidad              INTEGER NOT NULL CHECK (cantidad > 0),
    precio_centavos_visto INTEGER NOT NULL CHECK (precio_centavos_visto >= 0),
    PRIMARY KEY (id_local, producto_id)
) STRICT;

-- Cola de salida. solicitud_uuid es la clave de idempotencia que viaja al servidor.
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

-- R2: a lo sumo una solicitud pendiente por borrador.
CREATE UNIQUE INDEX uq_cola_un_pendiente_por_borrador ON cola_sync (id_local) WHERE estado = 'PENDIENTE';
CREATE INDEX idx_producto_catalogo ON producto_cache (disponible, eliminado, categoria, nombre);

-- R1: no se encola un borrador vacío.
CREATE TRIGGER trg_cola_borrador_con_items
BEFORE INSERT ON cola_sync
WHEN NOT EXISTS (SELECT 1 FROM item_borrador WHERE id_local = NEW.id_local)
BEGIN
    SELECT RAISE(ABORT, 'El borrador no tiene ítems: no se puede enviar');
END;

-- Una vez enviado, el borrador no se edita: lo que el servidor evalúa es lo que se envió.
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

-- Una solicitud resuelta no cambia de resultado (historial confiable).
CREATE TRIGGER trg_cola_resuelta_inmutable
BEFORE UPDATE OF estado, respuesta ON cola_sync
WHEN OLD.estado <> 'PENDIENTE'
BEGIN
    SELECT RAISE(ABORT, 'La solicitud ya fue resuelta por el servidor');
END;

-- Catálogo que ve la persona en la feria, con o sin conexión.
CREATE VIEW v_catalogo AS
SELECT id, nombre, categoria, precio_centavos, stock_visto
FROM producto_cache
WHERE disponible = 1 AND eliminado = 0
ORDER BY categoria, nombre;
