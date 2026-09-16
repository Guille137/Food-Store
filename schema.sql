-- ============================================================
-- TRABAJO PRÁCTICO N.º 1 - FOOD STORE
-- PARTE 4 - DDL EN POSTGRESQL
-- ============================================================


-- ============================================================
-- ELIMINACIÓN PREVIA
-- ============================================================

DROP TABLE IF EXISTS detalle_pedido CASCADE;
DROP TABLE IF EXISTS pedido CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;

DROP TYPE IF EXISTS estado_pedido CASCADE;
DROP TYPE IF EXISTS forma_pago CASCADE;


-- ============================================================
-- TIPOS ENUMERADOS
-- ============================================================

CREATE TYPE forma_pago AS ENUM (
    'EFECTIVO',
    'TARJETA',
    'TRANSFERENCIA'
);

CREATE TYPE estado_pedido AS ENUM (
    'PENDIENTE',
    'CONFIRMADO',
    'ENTREGADO',
    'CANCELADO'
);


-- ============================================================
-- TABLA CATEGORIA
-- ============================================================

CREATE TABLE categoria (
    id_categoria INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(50) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_categoria
        PRIMARY KEY (id_categoria),

    CONSTRAINT uq_categoria_nombre
        UNIQUE (nombre)
);


-- ============================================================
-- TABLA CLIENTE
-- ============================================================

CREATE TABLE cliente (
    id_cliente INTEGER GENERATED ALWAYS AS IDENTITY,
    correo_electronico VARCHAR(150) NOT NULL,
    nro_telefono VARCHAR(30),
    nombre VARCHAR(50) NOT NULL,
    apellido VARCHAR(50) NOT NULL,

    CONSTRAINT pk_cliente
        PRIMARY KEY (id_cliente),

    CONSTRAINT uq_cliente_correo
        UNIQUE (correo_electronico)
);


-- ============================================================
-- TABLA PRODUCTO
-- ============================================================

CREATE TABLE producto (
    id_producto INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(100) NOT NULL,
    precio_lista NUMERIC(10,2) NOT NULL,
    stock INTEGER NOT NULL DEFAULT 0,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    categoria_id INTEGER NOT NULL,

    CONSTRAINT pk_producto
        PRIMARY KEY (id_producto),

    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (categoria_id)
        REFERENCES categoria(id_categoria)
        ON DELETE RESTRICT,

    CONSTRAINT uq_producto_nombre
        UNIQUE (nombre),

    CONSTRAINT chk_producto_precio
        CHECK (precio_lista >= 0),

    CONSTRAINT chk_producto_stock
        CHECK (stock >= 0)
);


-- ============================================================
-- TABLA PEDIDO
-- ============================================================

CREATE TABLE pedido (
    id_pedido INTEGER GENERATED ALWAYS AS IDENTITY,
    fecha TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado estado_pedido NOT NULL DEFAULT 'PENDIENTE',
    forma_pago forma_pago NOT NULL,
    cliente_id INTEGER NOT NULL,

    CONSTRAINT pk_pedido
        PRIMARY KEY (id_pedido),

    CONSTRAINT fk_pedido_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES cliente(id_cliente)
        ON DELETE RESTRICT
);


-- ============================================================
-- TABLA DETALLE_PEDIDO
-- ============================================================

CREATE TABLE detalle_pedido (
    id_pedido INTEGER NOT NULL,
    id_producto INTEGER NOT NULL,
    precio_unitario NUMERIC(10,2) NOT NULL,
    cantidad INTEGER NOT NULL,

    CONSTRAINT pk_detalle_pedido
        PRIMARY KEY (id_pedido, id_producto),

    CONSTRAINT fk_detalle_pedido_pedido
        FOREIGN KEY (id_pedido)
        REFERENCES pedido(id_pedido)
        ON DELETE RESTRICT,

    CONSTRAINT fk_detalle_pedido_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto(id_producto)
        ON DELETE RESTRICT,

    CONSTRAINT chk_detalle_precio
        CHECK (precio_unitario >= 0),

    CONSTRAINT chk_detalle_cantidad
        CHECK (cantidad > 0)
);


-- ============================================================
-- ÍNDICES
-- ============================================================

-- Acelera la búsqueda de los pedidos de un cliente.
CREATE INDEX idx_pedido_cliente
    ON pedido(cliente_id);

-- Acelera la búsqueda de productos de una categoría.
CREATE INDEX idx_producto_categoria
    ON producto(categoria_id);


-- ============================================================
-- EJECUCIÓN / COMPROBACIÓN
-- ============================================================

-- Comprobar que las tablas fueron creadas correctamente.
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
      'categoria',
      'cliente',
      'producto',
      'pedido',
      'detalle_pedido'
  )
ORDER BY table_name;

-- Comprobar la estructura de las tablas.
SELECT
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'categoria',
      'cliente',
      'producto',
      'pedido',
      'detalle_pedido'
  )
ORDER BY table_name, ordinal_position;