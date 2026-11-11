-- Unidad 4 · Paso 2: las dependencias funcionales se VALIDAN contra los datos.
-- Una DF X -> Y se cumple en la instancia si ningún valor de X aparece con dos
-- valores distintos de Y. Se cuenta cuántos valores de X la violan:
--   * sobre la tabla cruda (tal como se cargó), y
--   * sobre la forma canónica (sin diferencias de mayúsculas/espacios y con las
--     correcciones aprobadas en legado.correccion_rubro).
-- Importante: que una DF se cumpla en los datos NO prueba que sea una regla del
-- negocio; que NO se cumpla sí prueba que no puede usarse como clave tal cual.
-- Solo lectura. No modifica nada.

CREATE FUNCTION pg_temp.violaciones(p_relacion text, p_det text, p_dep text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint;
BEGIN
    EXECUTE format(
        'SELECT count(*) FROM (SELECT 1 FROM %s WHERE (%s) IS NOT NULL
           GROUP BY %s HAVING count(DISTINCT (%s)) > 1) AS x',
        p_relacion, p_det, p_det, p_dep) INTO v;
    RETURN v;
END $$;

WITH hipotesis (orden, df, det_crudo, dep_crudo, det_canon, dep_canon) AS (VALUES
    (1, 'nro_planilla -> fecha, cliente, forma_pago, estado, repartidor',
        'nro_planilla', 'fecha_txt, cliente_email, medio_pago, estado, repartidor_legajo',
        'nro_planilla', 'fecha, email, forma_pago, estado, legajo'),
    (2, 'email -> nombre, apellido',
        'cliente_email', 'cliente_nombre, cliente_apellido',
        'email', 'nombre, apellido'),
    (3, 'email -> telefono',
        'cliente_email', 'cliente_telefono', 'email', 'telefono'),
    (4, 'producto -> rubro',
        'producto', 'rubro', 'producto', 'rubro'),
    (5, 'producto -> precio_unit',
        'producto', 'precio_unit', 'producto', 'precio_unit'),
    (6, '(nro_planilla, producto) -> precio_unit',
        'nro_planilla, producto', 'precio_unit', 'nro_planilla, producto', 'precio_unit'),
    (7, '(nro_planilla, producto) -> cantidad',
        'nro_planilla, producto', 'cantidad', 'nro_planilla, producto', 'cantidad'),
    (8, 'repartidor_legajo -> repartidor_nombre, zona',
        'repartidor_legajo', 'repartidor_nombre, zona', 'legajo', 'repartidor, zona'),
    (9, 'zona -> repartidor_legajo',
        'zona', 'repartidor_legajo', 'zona', 'legajo')
)
SELECT orden, df,
       pg_temp.violaciones('legado.venta_planilla', det_crudo, dep_crudo)  AS viola_crudo,
       pg_temp.violaciones('legado.v_venta_canonica', det_canon, dep_canon) AS viola_canonico
FROM hipotesis
ORDER BY orden;

-- Detalle de las violaciones que sobreviven a la forma canónica.
\echo '--- DF 3: correos con más de un teléfono'
SELECT email, count(DISTINCT telefono) AS telefonos,
       string_agg(DISTINCT telefono, ' | ' ORDER BY telefono) AS valores
FROM legado.v_venta_canonica WHERE email IS NOT NULL
GROUP BY email HAVING count(DISTINCT telefono) > 1 ORDER BY email;

\echo '--- DF 4 (cruda): productos con más de un rubro escrito'
SELECT lower(btrim(producto)) AS producto,
       string_agg(DISTINCT rubro, ' | ' ORDER BY rubro) AS rubros_escritos
FROM legado.venta_planilla
GROUP BY lower(btrim(producto)) HAVING count(DISTINCT lower(btrim(rubro))) > 1 ORDER BY 1;

\echo '--- DF 7: doble carga del mismo producto en una planilla'
SELECT nro_planilla, producto, count(*) AS renglones, sum(cantidad) AS cantidad_total
FROM legado.v_venta_canonica
GROUP BY nro_planilla, producto HAVING count(*) > 1 ORDER BY 1;

\echo '--- Planillas que no se pueden migrar (sin correo o sin fecha válida)'
SELECT nro_planilla, count(*) AS renglones
FROM legado.v_venta_canonica
WHERE email IS NULL OR fecha IS NULL OR forma_pago IS NULL OR estado IS NULL
GROUP BY nro_planilla ORDER BY 1;
