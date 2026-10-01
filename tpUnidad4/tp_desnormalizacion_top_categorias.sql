-- Unidad 4, Parte 2. Ejecutar después de Parte 1, en transacción externa.
-- Se conserva el esquema público. El día comercial se define en Argentina.
-- El proyecto no tiene eliminado en pedido/detalle: se incluyen sus filas
-- existentes, sin inventar un filtro por estado ni borrar ventas históricas
-- cuando producto/categoria pasan a activo=false.
-- El subtotal es cantidad * precio_unitario (precio histórico).
-- Bloquea escrituras durante instalación para evitar una ventana sin sincronía.
LOCK TABLE public.categoria, public.producto, public.pedido, public.detalle_pedido
IN SHARE ROW EXCLUSIVE MODE;

CREATE VIEW unidad4.ventas_categoria_fuente AS
SELECT (ped.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE AS fecha,
       c.id_categoria, c.nombre AS categoria,
       SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM public.detalle_pedido dp
JOIN public.producto pr ON pr.id_producto = dp.id_producto
JOIN public.categoria c ON c.id_categoria = pr.categoria_id
JOIN public.pedido ped ON ped.id_pedido = dp.id_pedido
GROUP BY 1, c.id_categoria, c.nombre;

-- Guarda TODOS los días: el cambio de día no exige reconstruir el objeto.
CREATE MATERIALIZED VIEW unidad4.ventas_categoria_diaria AS
SELECT * FROM unidad4.ventas_categoria_fuente;
CREATE UNIQUE INDEX u4_ventas_dia_categoria
ON unidad4.ventas_categoria_diaria(fecha,id_categoria);
CREATE INDEX u4_ventas_top ON unidad4.ventas_categoria_diaria
(fecha,total_vendido DESC,categoria);

CREATE FUNCTION unidad4.bloquear_ventas() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'La sincronización Unidad 4 requiere READ COMMITTED' USING ERRCODE='0A000';
    END IF;
    PERFORM pg_advisory_xact_lock(42004,2);
    RETURN NULL;
END $$;
CREATE FUNCTION unidad4.sincronizar_ventas() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW unidad4.ventas_categoria_diaria;
    RETURN NULL;
END $$;

-- Una actualización por sentencia, no una por fila. Se incluyen TRUNCATE,
-- cambios de fecha, de categoría y de nombre; no solo altas de detalles.
DO $$ DECLARE t TEXT; BEGIN
    FOREACH t IN ARRAY ARRAY['categoria','producto','pedido','detalle_pedido'] LOOP
        EXECUTE format('CREATE TRIGGER u4_ventas_bloqueo BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION unidad4.bloquear_ventas()',t);
        EXECUTE format('CREATE TRIGGER u4_ventas_sincronia AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION unidad4.sincronizar_ventas()',t);
    END LOOP;
END $$;

CREATE VIEW unidad4.top_categorias_normalizado AS
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM public.detalle_pedido dp
JOIN public.producto pr ON pr.id_producto=dp.id_producto
JOIN public.categoria c ON c.id_categoria=pr.categoria_id
JOIN public.pedido ped ON ped.id_pedido=dp.id_pedido
WHERE ped.fecha >= ((CURRENT_TIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires')::date::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
  AND ped.fecha < (((CURRENT_TIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires')::date+1)::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
GROUP BY c.nombre
ORDER BY total_vendido DESC, c.nombre
LIMIT 5;
CREATE VIEW unidad4.top_categorias_materializado AS
SELECT categoria,total_vendido FROM unidad4.ventas_categoria_diaria
WHERE fecha=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires')::date
ORDER BY total_vendido DESC,categoria
LIMIT 5;

-- Compara ambas direcciones, todos los días, nombres e importes exactos.
-- Detecta también filas sobrantes y la desaparición de la última venta.
CREATE VIEW unidad4.auditoria_ventas AS
(SELECT * FROM unidad4.ventas_categoria_fuente
 EXCEPT ALL SELECT * FROM unidad4.ventas_categoria_diaria)
UNION ALL
(SELECT * FROM unidad4.ventas_categoria_diaria
 EXCEPT ALL SELECT * FROM unidad4.ventas_categoria_fuente);

EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM unidad4.top_categorias_normalizado;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM unidad4.top_categorias_materializado;
SELECT * FROM unidad4.auditoria_ventas; -- Debe devolver 0 filas.
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM unidad4.auditoria_ventas) THEN
        RAISE EXCEPTION 'La materializada no coincide con su fuente';
    END IF;
END $$;
