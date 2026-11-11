-- Unidad 4 · Paso 3: migración de la planilla heredada al modelo en BCNF.
-- Spec: .kiro/specs/u4-migracion-legado/ (requirements, design, tasks).
--
-- NO contiene BEGIN ni COMMIT. Quien lo ejecuta decide:
--   ensayo:      psql ... -c BEGIN -f 03_migracion.sql -f 04_verificar_migracion.sql -c ROLLBACK
--   definitivo:  psql ... -c BEGIN -f 03_migracion.sql -f 04_verificar_migracion.sql -c COMMIT
-- Con ON_ERROR_STOP=1 cualquier error corta la sesión y PostgreSQL revierte todo,
-- incluido el DDL (en PostgreSQL el DDL es transaccional).
--
-- La planilla heredada no se modifica ni se borra: queda como fuente para auditar.

SET LOCAL lock_timeout = '10s';

-- LOCK falla fuera de una transacción: impide ejecutar este script "suelto".
LOCK TABLE legado.venta_planilla IN SHARE MODE;
LOCK TABLE public.categoria, public.producto, public.cliente, public.pedido,
           public.detalle_pedido IN SHARE ROW EXCLUSIVE MODE;

-- ---------------------------------------------------------------------------
-- 1. Estructuras nuevas
-- ---------------------------------------------------------------------------
CREATE SCHEMA migracion;
COMMENT ON SCHEMA migracion IS 'Trazabilidad de la migración del legado: mapas, cuarentena y discrepancias.';

CREATE TABLE migracion.lote (
    id_lote       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iniciado_en   timestamptz NOT NULL DEFAULT clock_timestamp(),
    ejecutado_por text NOT NULL DEFAULT session_user,
    renglones_legado integer NOT NULL,
    estado        text NOT NULL DEFAULT 'APLICADO' CHECK (estado = 'APLICADO')
);
INSERT INTO migracion.lote (renglones_legado) SELECT count(*) FROM legado.venta_planilla;

-- Renglones que no se pueden migrar: se guardan completos, con el motivo.
CREATE TABLE migracion.cuarentena (LIKE legado.venta_planilla, motivo text NOT NULL);

-- Valores del legado que NO pasaron al modelo nuevo porque contradicen otro
-- dato. No se descartan en silencio: quedan registrados con la regla aplicada.
CREATE TABLE migracion.discrepancia (
    entidad          text NOT NULL,
    clave            text NOT NULL,
    atributo         text NOT NULL,
    valor_legado     text,
    valor_conservado text,
    regla            text NOT NULL
);

CREATE TABLE migracion.mapa_categoria (
    rubro        text PRIMARY KEY,
    id_categoria integer NOT NULL REFERENCES public.categoria,
    creado       boolean NOT NULL
);
CREATE TABLE migracion.mapa_producto (
    producto    text PRIMARY KEY,
    id_producto integer NOT NULL REFERENCES public.producto,
    creado      boolean NOT NULL
);
CREATE TABLE migracion.mapa_cliente (
    email      text PRIMARY KEY,
    id_cliente integer NOT NULL REFERENCES public.cliente,
    creado     boolean NOT NULL
);
-- La FK hacia pedido se agrega en el paso 6, cuando los pedidos ya existen:
-- el id se reserva antes de insertar el pedido.
CREATE TABLE migracion.mapa_pedido (
    nro_planilla integer PRIMARY KEY,
    id_pedido    integer NOT NULL UNIQUE
);

-- Entidades que la planilla escondía dentro de cada renglón.
-- repartidor_legajo -> nombre, zona  pasa a ser la clave primaria de repartidor.
CREATE TABLE public.zona (
    id_zona integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre  varchar(50) NOT NULL UNIQUE
);
CREATE TABLE public.repartidor (
    id_repartidor integer PRIMARY KEY,             -- legajo del sistema anterior
    nombre        varchar(100) NOT NULL,
    zona_id       integer NOT NULL REFERENCES public.zona ON DELETE RESTRICT
);
-- nro_planilla -> repartidor: un pedido tiene a lo sumo una entrega.
CREATE TABLE public.entrega (
    id_pedido     integer PRIMARY KEY REFERENCES public.pedido ON DELETE RESTRICT,
    repartidor_id integer NOT NULL REFERENCES public.repartidor ON DELETE RESTRICT
);
CREATE INDEX idx_entrega_repartidor ON public.entrega (repartidor_id);
CREATE INDEX idx_repartidor_zona ON public.repartidor (zona_id);

-- ---------------------------------------------------------------------------
-- 2. Cuarentena: planillas con datos obligatorios ausentes o ilegibles
-- ---------------------------------------------------------------------------
INSERT INTO migracion.cuarentena
SELECT v.*, 'Planilla sin correo de cliente, fecha, forma de pago o estado reconocible'
FROM legado.venta_planilla AS v
WHERE v.nro_planilla IN (
    SELECT nro_planilla FROM legado.v_venta_canonica
    WHERE email IS NULL OR fecha IS NULL OR forma_pago IS NULL OR estado IS NULL
       OR producto IS NULL OR rubro IS NULL OR precio_unit IS NULL OR cantidad IS NULL);

-- Instantánea canónica de lo que SÍ se migra. Todo lo que sigue lee de acá.
CREATE TEMP TABLE t_canon ON COMMIT DROP AS
SELECT c.* FROM legado.v_venta_canonica AS c
WHERE c.nro_planilla NOT IN (SELECT nro_planilla FROM migracion.cuarentena);

-- Precondición comprobada, no supuesta: dentro de una planilla el mismo producto
-- tiene un único precio (DF 6). Si no fuera así, sumar cantidades perdería datos.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM t_canon GROUP BY nro_planilla, producto
               HAVING count(DISTINCT precio_unit) > 1) THEN
        RAISE EXCEPTION 'Hay un producto con dos precios en la misma planilla: migración detenida';
    END IF;
    IF EXISTS (SELECT 1 FROM t_canon GROUP BY nro_planilla
               HAVING count(DISTINCT (fecha, email, forma_pago, estado, legajo)) > 1) THEN
        RAISE EXCEPTION 'Una planilla tiene dos cabeceras distintas: migración detenida';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Categorías y productos
-- ---------------------------------------------------------------------------
-- Los rubros que no existen se crean inactivos: no forman parte del catálogo actual.
WITH nuevos AS (
    INSERT INTO public.categoria (nombre, activo)
    SELECT initcap(r.rubro), FALSE
    FROM (SELECT DISTINCT rubro FROM t_canon) AS r
    WHERE NOT EXISTS (SELECT 1 FROM public.categoria c WHERE lower(c.nombre) = r.rubro)
    ORDER BY 1
    RETURNING id_categoria, lower(nombre) AS rubro
)
INSERT INTO migracion.mapa_categoria SELECT rubro, id_categoria, TRUE FROM nuevos;

INSERT INTO migracion.mapa_categoria
SELECT r.rubro, c.id_categoria, FALSE
FROM (SELECT DISTINCT rubro FROM t_canon) AS r
JOIN public.categoria AS c ON lower(c.nombre) = r.rubro
WHERE NOT EXISTS (SELECT 1 FROM migracion.mapa_categoria m WHERE m.rubro = r.rubro);

-- Producto existente: se respeta el catálogo actual. Producto solo del legado:
-- se crea inactivo, sin stock, con el precio de su última venta y la grafía original.
WITH ultimo AS (
    SELECT DISTINCT ON (t.producto) t.producto, t.rubro, t.precio_unit
    FROM t_canon AS t
    ORDER BY t.producto, t.fecha DESC, t.nro_planilla DESC, t.renglon DESC
), grafia AS (
    SELECT lower(btrim(producto)) AS producto, min(btrim(producto)) AS nombre
    FROM legado.venta_planilla GROUP BY 1
), nuevos AS (
    INSERT INTO public.producto (nombre, precio_lista, stock, activo, categoria_id)
    SELECT g.nombre, u.precio_unit, 0, FALSE, mc.id_categoria
    FROM ultimo AS u
    JOIN grafia AS g USING (producto)
    JOIN migracion.mapa_categoria AS mc ON mc.rubro = u.rubro
    WHERE NOT EXISTS (SELECT 1 FROM public.producto p WHERE lower(p.nombre) = u.producto)
    ORDER BY g.nombre
    RETURNING id_producto, lower(nombre) AS producto
)
INSERT INTO migracion.mapa_producto SELECT producto, id_producto, TRUE FROM nuevos;

INSERT INTO migracion.mapa_producto
SELECT x.producto, p.id_producto, FALSE
FROM (SELECT DISTINCT producto FROM t_canon) AS x
JOIN public.producto AS p ON lower(p.nombre) = x.producto
WHERE NOT EXISTS (SELECT 1 FROM migracion.mapa_producto m WHERE m.producto = x.producto);

-- Si el rubro del legado no coincide con la categoría vigente, manda el catálogo
-- actual y la diferencia queda registrada.
INSERT INTO migracion.discrepancia
SELECT DISTINCT 'producto', t.producto, 'rubro', t.rubro, lower(c.nombre),
       'Producto ya existente: se conserva la categoría del catálogo vigente'
FROM t_canon AS t
JOIN migracion.mapa_producto AS mp ON mp.producto = t.producto
JOIN public.producto AS p ON p.id_producto = mp.id_producto
JOIN public.categoria AS c ON c.id_categoria = p.categoria_id
WHERE lower(c.nombre) <> t.rubro;

-- ---------------------------------------------------------------------------
-- 4. Clientes
-- ---------------------------------------------------------------------------
-- email -> telefono NO se cumple en los datos (DF 3): se toma el de la venta más
-- reciente y los anteriores se guardan en discrepancia.
CREATE TEMP TABLE t_cliente ON COMMIT DROP AS
SELECT DISTINCT ON (email) email, nombre, apellido, telefono
FROM t_canon
ORDER BY email, fecha DESC, nro_planilla DESC;

WITH nuevos AS (
    INSERT INTO public.cliente (correo_electronico, nro_telefono, nombre, apellido)
    SELECT t.email, t.telefono, t.nombre, t.apellido
    FROM t_cliente AS t
    WHERE NOT EXISTS (SELECT 1 FROM public.cliente c WHERE lower(c.correo_electronico) = t.email)
    ORDER BY t.email
    RETURNING id_cliente, correo_electronico
)
INSERT INTO migracion.mapa_cliente SELECT correo_electronico, id_cliente, TRUE FROM nuevos;

INSERT INTO migracion.mapa_cliente
SELECT t.email, c.id_cliente, FALSE
FROM t_cliente AS t
JOIN public.cliente AS c ON lower(c.correo_electronico) = t.email
WHERE NOT EXISTS (SELECT 1 FROM migracion.mapa_cliente m WHERE m.email = t.email);

INSERT INTO migracion.discrepancia
SELECT DISTINCT 'cliente', t.email, 'telefono', t.telefono, c.nro_telefono,
       CASE WHEN m.creado THEN 'Cliente nuevo: se conserva el teléfono de la venta más reciente'
            ELSE 'Cliente ya existente: se conserva el teléfono vigente' END
FROM t_canon AS t
JOIN migracion.mapa_cliente AS m ON m.email = t.email
JOIN public.cliente AS c ON c.id_cliente = m.id_cliente
WHERE t.telefono IS DISTINCT FROM c.nro_telefono;

INSERT INTO migracion.discrepancia
SELECT DISTINCT 'cliente', t.email, 'nombre_apellido', t.nombre || ' ' || t.apellido,
       c.nombre || ' ' || c.apellido, 'Cliente ya existente: se conserva el nombre vigente'
FROM t_canon AS t
JOIN migracion.mapa_cliente AS m ON m.email = t.email
JOIN public.cliente AS c ON c.id_cliente = m.id_cliente
WHERE (t.nombre, t.apellido) IS DISTINCT FROM (c.nombre, c.apellido);

-- ---------------------------------------------------------------------------
-- 5. Zonas y repartidores
-- ---------------------------------------------------------------------------
INSERT INTO public.zona (nombre)
SELECT DISTINCT zona FROM t_canon WHERE zona IS NOT NULL ORDER BY 1;

INSERT INTO public.repartidor (id_repartidor, nombre, zona_id)
SELECT DISTINCT t.legajo, t.repartidor, z.id_zona
FROM t_canon AS t JOIN public.zona AS z ON z.nombre = t.zona
WHERE t.legajo IS NOT NULL
ORDER BY t.legajo;       -- si legajo -> nombre, zona no se cumpliera, falla la PK

-- ---------------------------------------------------------------------------
-- 6. Pedidos, líneas y entregas
-- ---------------------------------------------------------------------------
-- Se reserva el id de cada pedido antes de insertarlo para poder mapearlo.
INSERT INTO migracion.mapa_pedido
SELECT nro_planilla, nextval(pg_get_serial_sequence('public.pedido', 'id_pedido'))
FROM (SELECT DISTINCT nro_planilla FROM t_canon ORDER BY 1) AS x;

-- Nacen PENDIENTE: es el único estado en que la regla R2 permite cargar líneas.
INSERT INTO public.pedido (id_pedido, fecha, estado, forma_pago, cliente_id)
OVERRIDING SYSTEM VALUE
SELECT mp.id_pedido, c.fecha, 'PENDIENTE', c.forma_pago::public.forma_pago, mc.id_cliente
FROM (SELECT DISTINCT nro_planilla, fecha, forma_pago, email FROM t_canon) AS c
JOIN migracion.mapa_pedido AS mp USING (nro_planilla)
JOIN migracion.mapa_cliente AS mc USING (email)
ORDER BY mp.id_pedido;

ALTER TABLE migracion.mapa_pedido
    ADD CONSTRAINT mapa_pedido_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.pedido;

-- Decisión documentada (design.md, D-3): durante la carga histórica se suspenden
-- SOLO las dos reglas que describen ventas nuevas (producto activo con stock y
-- categoría activa). Siguen activas PK, FK, CHECK, la regla de pedido PENDIENTE
-- y la sincronización de la Unidad 4. Si la transacción se revierte, también se
-- revierte esta suspensión.
ALTER TABLE public.detalle_pedido DISABLE TRIGGER trg_validar_producto_y_stock_detalle;
ALTER TABLE public.detalle_pedido DISABLE TRIGGER trg_tpi_categorias_insert;

-- La doble carga (DF 7) se resuelve sumando cantidades: la PK es (pedido, producto).
INSERT INTO public.detalle_pedido (id_pedido, id_producto, precio_unitario, cantidad)
SELECT mp.id_pedido, mpr.id_producto, max(t.precio_unit), sum(t.cantidad)
FROM t_canon AS t
JOIN migracion.mapa_pedido AS mp USING (nro_planilla)
JOIN migracion.mapa_producto AS mpr USING (producto)
GROUP BY mp.id_pedido, mpr.id_producto
ORDER BY mp.id_pedido, mpr.id_producto;

ALTER TABLE public.detalle_pedido ENABLE TRIGGER trg_validar_producto_y_stock_detalle;
ALTER TABLE public.detalle_pedido ENABLE TRIGGER trg_tpi_categorias_insert;

-- Estado final por las transiciones permitidas (PENDIENTE -> CONFIRMADO -> ENTREGADO).
UPDATE public.pedido AS p SET estado = 'CANCELADO'
FROM migracion.mapa_pedido AS mp
WHERE mp.id_pedido = p.id_pedido
  AND mp.nro_planilla IN (SELECT nro_planilla FROM t_canon WHERE estado = 'CANCELADO');
UPDATE public.pedido AS p SET estado = 'CONFIRMADO'
FROM migracion.mapa_pedido AS mp
WHERE mp.id_pedido = p.id_pedido
  AND mp.nro_planilla IN (SELECT nro_planilla FROM t_canon WHERE estado = 'ENTREGADO');
UPDATE public.pedido AS p SET estado = 'ENTREGADO'
FROM migracion.mapa_pedido AS mp
WHERE mp.id_pedido = p.id_pedido AND p.estado = 'CONFIRMADO';

INSERT INTO public.entrega (id_pedido, repartidor_id)
SELECT DISTINCT mp.id_pedido, t.legajo
FROM t_canon AS t JOIN migracion.mapa_pedido AS mp USING (nro_planilla)
WHERE t.legajo IS NOT NULL
ORDER BY 1;

-- Los triggers suspendidos deben quedar habilitados antes de terminar.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_trigger
               WHERE tgrelid = 'public.detalle_pedido'::regclass
                 AND NOT tgisinternal AND tgenabled = 'D') THEN
        RAISE EXCEPTION 'Quedó un trigger deshabilitado en detalle_pedido';
    END IF;
END $$;

SELECT (SELECT count(*) FROM migracion.mapa_pedido)                     AS pedidos_migrados,
       (SELECT count(*) FROM migracion.mapa_cliente WHERE creado)       AS clientes_nuevos,
       (SELECT count(*) FROM migracion.mapa_producto WHERE creado)      AS productos_nuevos,
       (SELECT count(*) FROM migracion.mapa_categoria WHERE creado)     AS categorias_nuevas,
       (SELECT count(*) FROM public.repartidor)                         AS repartidores,
       (SELECT count(*) FROM migracion.cuarentena)                      AS renglones_en_cuarentena,
       (SELECT count(*) FROM migracion.discrepancia)                    AS discrepancias;
