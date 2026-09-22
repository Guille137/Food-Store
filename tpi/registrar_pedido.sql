-- El llamador controla BEGIN/COMMIT/ROLLBACK. No hay confirmaciones parciales.
-- JSONB: [{"id_producto": 1, "cantidad": 2}, ...]. No acepta precios del cliente.
CREATE PROCEDURE public.tpi_registrar_pedido(
    IN p_cliente_id integer,
    IN p_forma_pago public.forma_pago,
    IN p_lineas jsonb,
    INOUT p_id_pedido integer DEFAULT NULL
)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_linea jsonb;
    v_producto record;
BEGIN
    IF p_id_pedido IS NOT NULL THEN
        RAISE EXCEPTION 'El id de salida debe recibirse como NULL' USING ERRCODE = '22023';
    END IF;
    IF jsonb_typeof(p_lineas) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Las líneas deben ser un arreglo JSONB' USING ERRCODE = '22023';
    END IF;
    IF jsonb_array_length(p_lineas) = 0 THEN
        RAISE EXCEPTION 'El pedido necesita al menos una línea' USING ERRCODE = '22023';
    END IF;
    FOR v_linea IN SELECT value FROM jsonb_array_elements(p_lineas) LOOP
        IF jsonb_typeof(v_linea) IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION 'Cada línea debe ser un objeto' USING ERRCODE = '22023';
        END IF;
        IF jsonb_typeof(v_linea->'id_producto') IS DISTINCT FROM 'number'
           OR jsonb_typeof(v_linea->'cantidad') IS DISTINCT FROM 'number'
           OR ((v_linea->>'id_producto') ~ '^[1-9][0-9]*$') IS NOT TRUE
           OR ((v_linea->>'cantidad') ~ '^[1-9][0-9]*$') IS NOT TRUE
           OR v_linea - ARRAY['id_producto','cantidad'] <> '{}'::jsonb THEN
            RAISE EXCEPTION 'Usar solo id_producto y cantidad, enteros positivos' USING ERRCODE = '22023';
        END IF;
        IF (v_linea->>'id_producto')::numeric > 2147483647
           OR (v_linea->>'cantidad')::numeric > 2147483647 THEN
            RAISE EXCEPTION 'Identificador o cantidad fuera del rango INTEGER' USING ERRCODE = '22023';
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lineas) e
               GROUP BY (e->>'id_producto')::integer HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'Un producto no puede repetirse en el pedido' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.pedido(cliente_id, forma_pago, estado)
    VALUES (p_cliente_id, p_forma_pago, 'PENDIENTE') RETURNING id_pedido INTO p_id_pedido;

    FOR v_linea IN SELECT value FROM jsonb_array_elements(p_lineas)
                  ORDER BY (value->>'id_producto')::integer LOOP
        SELECT id_producto, precio_lista INTO v_producto
        FROM public.producto WHERE id_producto = (v_linea->>'id_producto')::integer
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Producto inexistente: %', v_linea->>'id_producto' USING ERRCODE = '23503';
        END IF;
        -- Los triggers validan estado, vigencia de producto/categoría y stock.
        INSERT INTO public.detalle_pedido(id_pedido, id_producto, precio_unitario, cantidad)
        VALUES (p_id_pedido, v_producto.id_producto, v_producto.precio_lista,
                (v_linea->>'cantidad')::integer);
    END LOOP;
END;
$$;
