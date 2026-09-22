-- Regla agregada en el TPI: no incorporar/editar líneas de categorías inactivas.
-- Cada sentencia dispone del conjunto completo de filas nuevas (tabla de transición).
CREATE FUNCTION public.tpi_validar_categorias_detalle()
RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_id integer;
    v_activa boolean;
BEGIN
    FOR v_id IN
        SELECT DISTINCT p.categoria_id
        FROM nuevas_lineas n JOIN public.producto p ON p.id_producto = n.id_producto
        ORDER BY p.categoria_id
    LOOP
        SELECT activo INTO v_activa FROM public.categoria
        WHERE id_categoria = v_id FOR SHARE;
        IF NOT FOUND OR NOT v_activa THEN
            RAISE EXCEPTION 'Categoría inexistente o inactiva: %', v_id USING ERRCODE = '23514';
        END IF;
    END LOOP;
    RETURN NULL; -- AFTER por sentencia: el valor de retorno no modifica filas.
END;
$$;

CREATE TRIGGER trg_tpi_categorias_insert
AFTER INSERT ON public.detalle_pedido
REFERENCING NEW TABLE AS nuevas_lineas
FOR EACH STATEMENT EXECUTE FUNCTION public.tpi_validar_categorias_detalle();

-- PostgreSQL no admite UPDATE OF columnas cuando se usa una tabla de transición.
CREATE TRIGGER trg_tpi_categorias_update
AFTER UPDATE ON public.detalle_pedido
REFERENCING NEW TABLE AS nuevas_lineas
FOR EACH STATEMENT EXECUTE FUNCTION public.tpi_validar_categorias_detalle();
