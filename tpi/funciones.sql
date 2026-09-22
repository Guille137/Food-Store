-- Total histórico: precio de venta y cantidad, incluso después de bajas del catálogo.
CREATE FUNCTION public.tpi_total_pedido(p_id_pedido integer)
RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_total numeric;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.pedido WHERE id_pedido = p_id_pedido) THEN
        RAISE EXCEPTION 'Pedido inexistente: %', p_id_pedido USING ERRCODE = 'P0002';
    END IF;
    SELECT COALESCE(sum(cantidad * precio_unitario), 0)
    INTO v_total
    FROM public.detalle_pedido WHERE id_pedido = p_id_pedido;
    RETURN v_total;
END;
$$;
