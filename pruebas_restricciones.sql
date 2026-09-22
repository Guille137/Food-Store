-- Ejecutar sobre datos_iniciales.sql, con restricciones instaladas.
-- El ejecutor abre BEGIN y termina en ROLLBACK; este archivo no confirma cambios.
-- Cada fallo esperado usa una subtransacción de PL/pgSQL (equivalente a savepoint).
CREATE OR REPLACE FUNCTION pg_temp.esperar_error(sentencia TEXT, codigo TEXT, fragmento TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE recibido TEXT; mensaje TEXT;
BEGIN
    BEGIN
        EXECUTE sentencia;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS recibido = RETURNED_SQLSTATE, mensaje = MESSAGE_TEXT;
    END;
    IF recibido IS DISTINCT FROM codigo OR position(fragmento IN COALESCE(mensaje, '')) = 0 THEN
        RAISE EXCEPTION 'Prueba fallida: %, esperado %, recibido %: %', sentencia, codigo, recibido, mensaje;
    END IF;
    RAISE NOTICE 'OK error esperado [%]: %', recibido, mensaje;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.verificar(condicion BOOLEAN, mensaje TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF condicion IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'Prueba fallida: %', mensaje; END IF;
    RAISE NOTICE 'OK: %', mensaje;
END;
$$;

-- Insertar y mover una línea entre dos pedidos pendientes es válido.
INSERT INTO detalle_pedido VALUES (1, 1, 1000, 1);
UPDATE detalle_pedido SET id_pedido = 2 WHERE id_pedido = 1 AND id_producto = 1;
SELECT pg_temp.verificar(EXISTS(SELECT 1 FROM detalle_pedido WHERE id_pedido=2 AND id_producto=1), 'Traslado entre pedidos pendientes');
UPDATE detalle_pedido SET id_pedido = 1 WHERE id_pedido = 2 AND id_producto = 1;
UPDATE detalle_pedido SET cantidad = 2 WHERE id_pedido = 1 AND id_producto = 1;
SELECT pg_temp.verificar((SELECT cantidad=2 FROM detalle_pedido WHERE id_pedido=1 AND id_producto=1), 'Cantidad editable mientras el pedido esta pendiente');

UPDATE pedido SET estado = 'CONFIRMADO' WHERE id_pedido = 1;
SELECT pg_temp.verificar((SELECT estado='CONFIRMADO' FROM pedido WHERE id_pedido=1), 'PENDIENTE a CONFIRMADO');
SELECT pg_temp.esperar_error($q$UPDATE pedido SET estado='PENDIENTE' WHERE id_pedido=1$q$, '23514', 'Transición de estado');
SELECT pg_temp.esperar_error($q$INSERT INTO detalle_pedido VALUES (1,3,900,1)$q$, '23514', 'está CONFIRMADO');
SELECT pg_temp.esperar_error($q$UPDATE detalle_pedido SET cantidad=1 WHERE id_pedido=1$q$, '23514', 'está CONFIRMADO');
SELECT pg_temp.esperar_error($q$DELETE FROM detalle_pedido WHERE id_pedido=1$q$, '23514', 'está CONFIRMADO');
SELECT pg_temp.esperar_error($q$UPDATE detalle_pedido SET id_pedido=2 WHERE id_pedido=1$q$, '23514', 'está CONFIRMADO');
INSERT INTO detalle_pedido VALUES (2,3,900,1);
SELECT pg_temp.esperar_error($q$UPDATE detalle_pedido SET id_pedido=1 WHERE id_pedido=2$q$, '23514', 'está CONFIRMADO');
DELETE FROM detalle_pedido WHERE id_pedido=2;
SELECT pg_temp.verificar(NOT EXISTS(SELECT 1 FROM detalle_pedido WHERE id_pedido=2), 'Borrado permitido en pedido pendiente');

-- Un producto INACTIVO con cantidad admisible prueba exclusivamente la actividad.
SELECT pg_temp.esperar_error($q$INSERT INTO detalle_pedido VALUES (2,2,800,1)$q$, '23514', 'está inactivo');
-- Un producto ACTIVO con stock 5 prueba exclusivamente la cantidad excesiva.
SELECT pg_temp.esperar_error($q$INSERT INTO detalle_pedido VALUES (2,3,900,6)$q$, '23514', 'Stock insuficiente');
INSERT INTO detalle_pedido VALUES (2,3,900,5);
SELECT pg_temp.verificar((SELECT cantidad=5 FROM detalle_pedido WHERE id_pedido=2 AND id_producto=3), 'Cantidad igual al stock aceptada');
SELECT pg_temp.esperar_error($q$UPDATE detalle_pedido SET cantidad=6 WHERE id_pedido=2$q$, '23514', 'Stock insuficiente');
SELECT pg_temp.esperar_error($q$UPDATE detalle_pedido SET id_producto=2 WHERE id_pedido=2$q$, '23514', 'está inactivo');
SELECT pg_temp.esperar_error($q$UPDATE detalle_pedido SET cantidad=0 WHERE id_pedido=2$q$, '23514', 'chk_detalle_cantidad');

UPDATE pedido SET estado='ENTREGADO' WHERE id_pedido=1;
SELECT pg_temp.verificar((SELECT estado='ENTREGADO' FROM pedido WHERE id_pedido=1), 'CONFIRMADO a ENTREGADO');
SELECT pg_temp.esperar_error($q$UPDATE pedido SET estado='CANCELADO' WHERE id_pedido=1$q$, '23514', 'Transición de estado');
UPDATE pedido SET estado='ENTREGADO' WHERE id_pedido=1;
UPDATE pedido SET estado='CONFIRMADO' WHERE id_pedido=2;
UPDATE pedido SET estado='CANCELADO' WHERE id_pedido=2;
SELECT pg_temp.verificar((SELECT estado='CANCELADO' FROM pedido WHERE id_pedido=2), 'CONFIRMADO a CANCELADO');
SELECT pg_temp.esperar_error($q$UPDATE pedido SET estado='PENDIENTE' WHERE id_pedido=2$q$, '23514', 'Transición de estado');
SELECT pg_temp.esperar_error($q$UPDATE pedido SET estado='ENTREGADO' WHERE id_pedido=3$q$, '23514', 'Transición de estado');
UPDATE pedido SET estado='CANCELADO' WHERE id_pedido=3;
SELECT pg_temp.verificar((SELECT estado='CANCELADO' FROM pedido WHERE id_pedido=3), 'PENDIENTE a CANCELADO');
