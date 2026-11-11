-- Unidad 4 · Paso 1: esquema heredado con redundancias.
-- Simula la planilla de ventas del sistema anterior de Food Store (año 2025):
-- UNA sola tabla, sin clave primaria, donde cada renglón repite los datos del
-- cliente, del producto, del rubro y del repartidor. Los datos son sintéticos y
-- deterministas; las anomalías se inyectan a propósito para que la validación
-- de dependencias funcionales tenga algo real que encontrar.
-- Ejecutar dentro de una transacción externa (BEGIN ... COMMIT/ROLLBACK).

CREATE SCHEMA legado;
COMMENT ON SCHEMA legado IS 'Planilla de ventas 2025 del sistema anterior. Solo lectura: nunca se modifica.';

CREATE TABLE legado.venta_planilla (
    nro_planilla      integer,
    renglon           integer,
    fecha_txt         text,      -- 'DD/MM/YYYY HH24:MI', hora de Buenos Aires
    cliente_email     text,
    cliente_nombre    text,
    cliente_apellido  text,
    cliente_telefono  text,
    producto          text,
    rubro             text,
    precio_unit       numeric(10,2),
    cantidad          integer,
    medio_pago        text,
    estado            text,
    repartidor_legajo integer,
    repartidor_nombre text,
    zona              text
);

CREATE FUNCTION pg_temp.h(t text) RETURNS integer
LANGUAGE sql IMMUTABLE AS $$ SELECT ('x' || substr(md5(t), 1, 7))::bit(28)::integer $$;

-- 400 planillas (1001 a 1400), de 1 a 3 renglones cada una.
WITH planilla AS (
    SELECT n AS nro,
           pg_temp.h('L-cli' || n) % 120 AS ci,       -- 0-59 cliente vigente, 60-119 solo del legado
           pg_temp.h('L-var' || n) AS var,
           TIMESTAMP '2025-03-01 10:00'
               + make_interval(mins => pg_temp.h('L-fecha' || n) % (270 * 24 * 60)) AS fecha,
           pg_temp.h('L-estado' || n) % 10 = 0 AS anulado,
           501 + pg_temp.h('L-rep' || n) % 6 AS legajo
    FROM generate_series(1001, 1400) AS n
), renglon AS (
    SELECT p.*, k, (pg_temp.h('L-prod' || p.nro) + k * 7) % 100 AS pi
    FROM planilla AS p
    CROSS JOIN LATERAL generate_series(1, 1 + pg_temp.h('L-lineas' || p.nro) % 3) AS k
)
INSERT INTO legado.venta_planilla
SELECT r.nro, r.k, to_char(r.fecha, 'DD/MM/YYYY HH24:MI'),
       -- El mismo correo aparece con mayúsculas o espacios según quién cargó la planilla.
       CASE WHEN r.ci < 60 THEN
                CASE r.var % 3 WHEN 0 THEN upper(c.correo_electronico)
                               WHEN 1 THEN c.correo_electronico || ' '
                               ELSE c.correo_electronico END
            ELSE 'legado' || r.ci || '@example.test' END,
       CASE WHEN r.ci < 60 THEN c.nombre
            ELSE (ARRAY['Abel','Berta','Ciro','Dora','Ezequiel','Flora'])[1 + r.ci % 6] END,
       CASE WHEN r.ci < 60 THEN c.apellido
            ELSE (ARRAY['Aguirre','Bustos','Campos','Duarte','Farias'])[1 + r.ci % 5] END,
       -- Anomalía D1: los clientes 60, 80 y 100 cambiaron de teléfono a mitad de año.
       CASE WHEN r.ci < 60 THEN c.nro_telefono
            WHEN r.ci % 20 = 0 AND r.fecha >= TIMESTAMP '2025-08-01'
                THEN '+54 9 351 5555-9' || lpad(r.ci::text, 3, '0')
            ELSE '+54 9 351 5555-0' || lpad(r.ci::text, 3, '0') END,
       CASE WHEN r.pi < 70 THEN CASE WHEN r.var % 4 = 0 THEN upper(pr.nombre) ELSE pr.nombre END
            WHEN r.pi < 85 THEN 'Minuta clasica ' || lpad((1 + r.pi % 10)::text, 2, '0')
            ELSE 'Pizza al molde ' || lpad((1 + r.pi % 10)::text, 2, '0') END,
       -- Anomalía D2: el rubro de "Pizza variedad 03" a veces se tipeó "Pizas".
       CASE WHEN r.pi < 70 THEN
                CASE WHEN pr.nombre = 'Pizza variedad 03' AND r.var % 2 = 0 THEN 'Pizas'
                     WHEN r.var % 5 = 0 THEN upper(cat.nombre) ELSE cat.nombre END
            WHEN r.pi < 85 THEN 'Minutas'
            ELSE 'Pizzas' END,
       -- El precio depende de la venta (planilla + producto), no solo del producto.
       CASE WHEN r.pi < 70
                THEN round(pr.precio_lista * (85 + pg_temp.h('L-pre' || r.nro || '-' || r.pi) % 16) / 100.0, 2)
            ELSE 500 + (pg_temp.h('L-pre' || r.nro || '-' || r.pi) % 40) * 50 END,
       1 + pg_temp.h('L-cant' || r.nro || '-' || r.k) % 4,
       CASE r.var % 3
            WHEN 0 THEN (ARRAY['Efectivo','EFECTIVO','efectivo '])[1 + r.nro % 3]
            WHEN 1 THEN (ARRAY['Tarjeta','TARJETA'])[1 + r.nro % 2]
            ELSE (ARRAY['Transf.','Transferencia'])[1 + r.nro % 2] END,
       CASE WHEN r.anulado THEN 'Anulado' ELSE 'Entregado' END,
       -- Una venta anulada nunca salió a reparto.
       CASE WHEN r.anulado THEN NULL ELSE r.legajo END,
       CASE WHEN r.anulado THEN NULL
            ELSE (ARRAY['Ramiro Paz','Sofia Luna','Tomas Rey','Vera Sol','Walter Gil','Yanina Cruz'])
                     [r.legajo - 500] END,
       CASE WHEN r.anulado THEN NULL
            ELSE CASE WHEN r.var % 7 = 0
                      THEN upper((ARRAY['Centro','Centro','Norte','Sur','Oeste','Oeste'])[r.legajo - 500])
                      ELSE (ARRAY['Centro','Centro','Norte','Sur','Oeste','Oeste'])[r.legajo - 500] END
       END
FROM renglon AS r
LEFT JOIN public.cliente  AS c   ON r.ci < 60 AND c.id_cliente = r.ci + 1
LEFT JOIN public.producto AS pr  ON r.pi < 70 AND pr.id_producto = r.pi + 1
LEFT JOIN public.categoria AS cat ON cat.id_categoria = pr.categoria_id;

-- Anomalía D4: doble carga. En 10 planillas se repitió el primer renglón
-- (mismo producto y precio) con otra cantidad.
INSERT INTO legado.venta_planilla
SELECT nro_planilla, 90 + renglon, fecha_txt, cliente_email, cliente_nombre, cliente_apellido,
       cliente_telefono, producto, rubro, precio_unit, cantidad + 1, medio_pago, estado,
       repartidor_legajo, repartidor_nombre, zona
FROM legado.venta_planilla
WHERE renglon = 1 AND nro_planilla % 40 = 0;

-- Anomalía D5: dos planillas sin correo de cliente (no se pueden migrar: van a cuarentena).
UPDATE legado.venta_planilla SET cliente_email = NULL WHERE nro_planilla = 1111;
UPDATE legado.venta_planilla SET cliente_email = '   ' WHERE nro_planilla = 1222;

-- Correcciones decididas por una persona tras revisar las violaciones (paso 2).
-- La migración no "adivina": solo aplica lo que figura en esta tabla.
CREATE TABLE legado.correccion_rubro (
    valor_legado   text PRIMARY KEY,   -- en minúsculas y sin espacios laterales
    valor_correcto text NOT NULL,
    motivo         text NOT NULL
);
INSERT INTO legado.correccion_rubro VALUES
    ('pizas', 'pizzas', 'Error de tipeo: el mismo producto figura como Pizzas en el resto de las planillas');

-- Forma canónica: quita diferencias de formato que no son diferencias de dato.
CREATE VIEW legado.v_venta_canonica AS
SELECT v.nro_planilla, v.renglon,
       to_timestamp(v.fecha_txt, 'DD/MM/YYYY HH24:MI')::timestamp
           AT TIME ZONE 'America/Argentina/Buenos_Aires' AS fecha,
       NULLIF(lower(btrim(v.cliente_email)), '') AS email,
       btrim(v.cliente_nombre) AS nombre,
       btrim(v.cliente_apellido) AS apellido,
       btrim(v.cliente_telefono) AS telefono,
       lower(btrim(v.producto)) AS producto,
       COALESCE(cr.valor_correcto, lower(btrim(v.rubro))) AS rubro,
       v.precio_unit, v.cantidad,
       CASE WHEN lower(btrim(v.medio_pago)) = 'efectivo' THEN 'EFECTIVO'
            WHEN lower(btrim(v.medio_pago)) = 'tarjeta' THEN 'TARJETA'
            WHEN lower(btrim(v.medio_pago)) IN ('transf.', 'transferencia') THEN 'TRANSFERENCIA'
       END AS forma_pago,
       CASE lower(btrim(v.estado)) WHEN 'entregado' THEN 'ENTREGADO'
                                   WHEN 'anulado' THEN 'CANCELADO' END AS estado,
       v.repartidor_legajo AS legajo,
       btrim(v.repartidor_nombre) AS repartidor,
       initcap(lower(btrim(v.zona))) AS zona
FROM legado.venta_planilla AS v
LEFT JOIN legado.correccion_rubro AS cr ON cr.valor_legado = lower(btrim(v.rubro));

REVOKE ALL ON SCHEMA legado FROM PUBLIC;

SELECT count(*) AS renglones, count(DISTINCT nro_planilla) AS planillas,
       count(DISTINCT cliente_email) AS correos_distintos_crudos,
       count(DISTINCT lower(btrim(cliente_email))) AS correos_distintos_canonicos
FROM legado.venta_planilla;
