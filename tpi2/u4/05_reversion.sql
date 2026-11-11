-- Unidad 4 · Plan de reversión, nivel 2: deshacer una migración YA CONFIRMADA.
-- (Nivel 1 = ROLLBACK antes de confirmar. Nivel 3 = restaurar el respaldo previo.)
--
-- NO contiene BEGIN ni COMMIT: ejecutar igual que la migración,
--   psql ... -c BEGIN -f 05_reversion.sql -c COMMIT      (o ROLLBACK para ensayar)
-- Borra únicamente lo que la migración creó, guiándose por los mapas. No toca
-- los pedidos, clientes ni productos que ya existían, ni la planilla heredada.
-- Límite conocido: los valores de secuencia consumidos no se devuelven (quedan
-- huecos en los identificadores; no afecta la integridad).

SET LOCAL lock_timeout = '10s';
LOCK TABLE public.categoria, public.producto, public.cliente, public.pedido,
           public.detalle_pedido IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
    IF to_regclass('migracion.lote') IS NULL THEN
        RAISE EXCEPTION 'No hay una migración aplicada para revertir';
    END IF;
    -- Si después de migrar alguien usó lo migrado, no se revierte a ciegas.
    IF EXISTS (SELECT 1 FROM public.pedido p
               JOIN migracion.mapa_cliente m ON m.id_cliente = p.cliente_id AND m.creado
               WHERE p.id_pedido NOT IN (SELECT id_pedido FROM migracion.mapa_pedido)) THEN
        RAISE EXCEPTION 'Un cliente creado por la migración ya tiene pedidos nuevos: revisar a mano';
    END IF;
    IF EXISTS (SELECT 1 FROM public.detalle_pedido d
               JOIN migracion.mapa_producto m ON m.id_producto = d.id_producto AND m.creado
               WHERE d.id_pedido NOT IN (SELECT id_pedido FROM migracion.mapa_pedido)) THEN
        RAISE EXCEPTION 'Un producto creado por la migración ya tiene ventas nuevas: revisar a mano';
    END IF;
END $$;

-- Se anotan los ids a borrar y se eliminan los mapas ANTES de borrar los datos:
-- los mapas tienen claves foráneas hacia pedido, cliente, producto y categoría.
CREATE TEMP TABLE t_borrar ON COMMIT DROP AS
SELECT 'pedido' AS tipo, id_pedido AS id FROM migracion.mapa_pedido
UNION ALL SELECT 'producto', id_producto FROM migracion.mapa_producto WHERE creado
UNION ALL SELECT 'categoria', id_categoria FROM migracion.mapa_categoria WHERE creado
UNION ALL SELECT 'cliente', id_cliente FROM migracion.mapa_cliente WHERE creado;

DROP SCHEMA migracion CASCADE;

DELETE FROM public.entrega
WHERE id_pedido IN (SELECT id FROM t_borrar WHERE tipo = 'pedido');

-- La regla R2 impide borrar líneas de pedidos que no están PENDIENTE. Para
-- deshacer una carga histórica se suspende solo durante este borrado.
ALTER TABLE public.detalle_pedido DISABLE TRIGGER trg_validar_edicion_detalle_pedido;
DELETE FROM public.detalle_pedido
WHERE id_pedido IN (SELECT id FROM t_borrar WHERE tipo = 'pedido');
ALTER TABLE public.detalle_pedido ENABLE TRIGGER trg_validar_edicion_detalle_pedido;

DELETE FROM public.pedido    WHERE id_pedido    IN (SELECT id FROM t_borrar WHERE tipo = 'pedido');
DELETE FROM public.producto  WHERE id_producto  IN (SELECT id FROM t_borrar WHERE tipo = 'producto');
DELETE FROM public.categoria WHERE id_categoria IN (SELECT id FROM t_borrar WHERE tipo = 'categoria');
DELETE FROM public.cliente   WHERE id_cliente   IN (SELECT id FROM t_borrar WHERE tipo = 'cliente');

DROP TABLE public.entrega;
DROP TABLE public.repartidor;
DROP TABLE public.zona;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_trigger
               WHERE tgrelid = 'public.detalle_pedido'::regclass
                 AND NOT tgisinternal AND tgenabled = 'D') THEN
        RAISE EXCEPTION 'Quedó un trigger deshabilitado en detalle_pedido';
    END IF;
    IF EXISTS (SELECT 1 FROM unidad4.auditoria_ventas) THEN
        RAISE EXCEPTION 'La materializada de la Unidad 4 quedó desincronizada';
    END IF;
END $$;

SELECT 'REVERSION APLICADA' AS resultado,
       (SELECT count(*) FROM public.pedido) AS pedidos,
       (SELECT count(*) FROM public.cliente) AS clientes,
       (SELECT count(*) FROM public.producto) AS productos,
       (SELECT count(*) FROM legado.venta_planilla) AS renglones_legado_intactos;
