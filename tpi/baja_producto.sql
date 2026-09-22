-- Baja lógica idempotente. Mantiene la fila, su nombre único y su historia de ventas.
CREATE PROCEDURE public.tpi_baja_producto(IN p_id_producto integer)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    UPDATE public.producto SET activo = false WHERE id_producto = p_id_producto;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Producto inexistente: %', p_id_producto USING ERRCODE = 'P0002';
    END IF;
END;
$$;
