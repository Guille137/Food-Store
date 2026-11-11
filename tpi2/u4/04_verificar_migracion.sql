-- Unidad 4 · Paso 4: prueba de que la migración no perdió ni inventó datos.
-- Se ejecuta en la MISMA transacción que 03_migracion.sql, antes de decidir
-- COMMIT o ROLLBACK. Cualquier diferencia lanza una excepción y aborta todo.

-- Lo que el legado dice, en forma canónica y con la doble carga ya sumada.
CREATE VIEW migracion.v_legado_esperado AS
SELECT c.nro_planilla, c.fecha, c.email, c.producto, c.precio_unit,
       sum(c.cantidad) AS cantidad, c.forma_pago, c.estado,
       c.legajo, lower(c.repartidor) AS repartidor, lower(c.zona) AS zona
FROM legado.v_venta_canonica AS c
WHERE c.nro_planilla NOT IN (SELECT nro_planilla FROM migracion.cuarentena)
GROUP BY c.nro_planilla, c.fecha, c.email, c.producto, c.precio_unit,
         c.forma_pago, c.estado, c.legajo, lower(c.repartidor), lower(c.zona);

-- Lo mismo, reconstruido SOLO con las tablas normalizadas (reunión sin pérdida).
CREATE VIEW migracion.v_reconstruccion AS
SELECT mp.nro_planilla, p.fecha, lower(cl.correo_electronico) AS email,
       lower(pr.nombre) AS producto, d.precio_unitario AS precio_unit,
       d.cantidad::bigint AS cantidad, p.forma_pago::text AS forma_pago,
       p.estado::text AS estado, r.id_repartidor AS legajo,
       lower(r.nombre) AS repartidor, lower(z.nombre) AS zona
FROM migracion.mapa_pedido AS mp
JOIN public.pedido AS p ON p.id_pedido = mp.id_pedido
JOIN public.cliente AS cl ON cl.id_cliente = p.cliente_id
JOIN public.detalle_pedido AS d ON d.id_pedido = p.id_pedido
JOIN public.producto AS pr ON pr.id_producto = d.id_producto
LEFT JOIN public.entrega AS e ON e.id_pedido = p.id_pedido
LEFT JOIN public.repartidor AS r ON r.id_repartidor = e.repartidor_id
LEFT JOIN public.zona AS z ON z.id_zona = r.zona_id;

-- Diferencias en los dos sentidos: faltantes y sobrantes.
CREATE VIEW migracion.v_diferencias AS
(SELECT 'falta_en_modelo_nuevo' AS problema, * FROM
    (SELECT * FROM migracion.v_legado_esperado EXCEPT ALL
     SELECT * FROM migracion.v_reconstruccion) AS a)
UNION ALL
(SELECT 'sobra_en_modelo_nuevo', * FROM
    (SELECT * FROM migracion.v_reconstruccion EXCEPT ALL
     SELECT * FROM migracion.v_legado_esperado) AS b);

\echo '--- Control 1: renglones del legado = migrados + cuarentena'
SELECT (SELECT count(*) FROM legado.venta_planilla) AS renglones_legado,
       (SELECT count(*) FROM legado.venta_planilla
        WHERE nro_planilla IN (SELECT nro_planilla FROM migracion.mapa_pedido)) AS renglones_migrados,
       (SELECT count(*) FROM migracion.cuarentena) AS renglones_cuarentena;

\echo '--- Control 2: importes'
SELECT (SELECT sum(precio_unit * cantidad) FROM migracion.v_legado_esperado) AS importe_legado,
       (SELECT sum(d.precio_unitario * d.cantidad)
        FROM public.detalle_pedido d JOIN migracion.mapa_pedido m USING (id_pedido)) AS importe_migrado;

\echo '--- Control 3: diferencias fila a fila (debe devolver 0 filas)'
SELECT * FROM migracion.v_diferencias;

\echo '--- Control 4: salvaguarda de la desnormalización Unidad 4 (debe devolver 0 filas)'
SELECT * FROM unidad4.auditoria_ventas;

\echo '--- Control 5: valores del legado no trasladados, con su regla'
SELECT entidad, atributo, regla, count(*) AS casos
FROM migracion.discrepancia GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

DO $$
DECLARE
    v_legado bigint; v_migrado bigint; v_cuarentena bigint;
    v_imp_legado numeric; v_imp_migrado numeric;
BEGIN
    SELECT count(*) INTO v_legado FROM legado.venta_planilla;
    SELECT count(*) INTO v_migrado FROM legado.venta_planilla
    WHERE nro_planilla IN (SELECT nro_planilla FROM migracion.mapa_pedido);
    SELECT count(*) INTO v_cuarentena FROM migracion.cuarentena;
    IF v_legado <> v_migrado + v_cuarentena THEN
        RAISE EXCEPTION 'Renglones sin destino: legado %, migrados %, cuarentena %',
            v_legado, v_migrado, v_cuarentena;
    END IF;

    SELECT sum(precio_unit * cantidad) INTO v_imp_legado FROM migracion.v_legado_esperado;
    SELECT sum(d.precio_unitario * d.cantidad) INTO v_imp_migrado
    FROM public.detalle_pedido d JOIN migracion.mapa_pedido m USING (id_pedido);
    IF v_imp_legado IS DISTINCT FROM v_imp_migrado THEN
        RAISE EXCEPTION 'Importes distintos: legado %, migrado %', v_imp_legado, v_imp_migrado;
    END IF;

    IF EXISTS (SELECT 1 FROM migracion.v_diferencias) THEN
        RAISE EXCEPTION 'La reconstrucción no coincide con el legado';
    END IF;
    IF EXISTS (SELECT 1 FROM unidad4.auditoria_ventas) THEN
        RAISE EXCEPTION 'La materializada de la Unidad 4 quedó desincronizada';
    END IF;

    -- Los datos de cliente creados por la migración salen de la venta más reciente.
    IF EXISTS (
        SELECT 1
        FROM migracion.mapa_cliente m
        JOIN public.cliente c ON c.id_cliente = m.id_cliente
        JOIN LATERAL (SELECT nombre, apellido, telefono FROM legado.v_venta_canonica v
                      WHERE v.email = m.email
                      ORDER BY v.fecha DESC, v.nro_planilla DESC LIMIT 1) AS u ON TRUE
        WHERE m.creado
          AND (c.nombre, c.apellido, c.nro_telefono) IS DISTINCT FROM (u.nombre, u.apellido, u.telefono)
    ) THEN
        RAISE EXCEPTION 'Un cliente nuevo no coincide con su venta más reciente';
    END IF;

    -- Todo rubro del legado coincide con la categoría del producto o está registrado.
    IF EXISTS (
        SELECT 1
        FROM legado.v_venta_canonica v
        JOIN migracion.mapa_producto mp ON mp.producto = v.producto
        JOIN public.producto p ON p.id_producto = mp.id_producto
        JOIN public.categoria c ON c.id_categoria = p.categoria_id
        WHERE v.nro_planilla IN (SELECT nro_planilla FROM migracion.mapa_pedido)
          AND lower(c.nombre) <> v.rubro
          AND NOT EXISTS (SELECT 1 FROM migracion.discrepancia d
                          WHERE d.entidad = 'producto' AND d.clave = v.producto
                            AND d.atributo = 'rubro' AND d.valor_legado = v.rubro)
    ) THEN
        RAISE EXCEPTION 'Hay un rubro del legado sin trasladar y sin registrar';
    END IF;

    RAISE NOTICE 'MIGRACION VERIFICADA: % renglones (% migrados, % en cuarentena), importe %',
        v_legado, v_migrado, v_cuarentena, v_imp_migrado;
END $$;
