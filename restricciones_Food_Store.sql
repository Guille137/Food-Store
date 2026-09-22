-- TP2 Food Store - restricciones de negocio
-- Ejecutar sobre una copia del esquema, dentro de BEGIN ... ROLLBACK primero.

-- R1: un pedido no puede regresar a PENDIENTE ni cambiar después de ENTREGADO/CANCELADO.
CREATE OR REPLACE FUNCTION validar_transicion_estado_pedido()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF (OLD.estado = 'PENDIENTE' AND NEW.estado IN ('CONFIRMADO', 'CANCELADO'))
       OR (OLD.estado = 'CONFIRMADO' AND NEW.estado IN ('ENTREGADO', 'CANCELADO')) THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Transición de estado no permitida: % -> %', OLD.estado, NEW.estado
        USING ERRCODE = '23514';
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_transicion_estado_pedido ON pedido;
CREATE TRIGGER trg_validar_transicion_estado_pedido
BEFORE UPDATE OF estado ON pedido
FOR EACH ROW
EXECUTE FUNCTION validar_transicion_estado_pedido();

-- R2: un detalle sólo puede agregarse, modificarse o borrarse mientras el pedido está PENDIENTE.
CREATE OR REPLACE FUNCTION validar_edicion_detalle_pedido()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_pedido INTEGER;
    v_ids INTEGER[];
    v_estado estado_pedido;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_ids := ARRAY[NEW.id_pedido];
    ELSIF TG_OP = 'DELETE' THEN
        v_ids := ARRAY[OLD.id_pedido];
    ELSE
        -- Mover una línea modifica tanto el pedido de origen como el de destino.
        v_ids := ARRAY[OLD.id_pedido, NEW.id_pedido];
    END IF;

    -- Orden fijo para que dos traslados no tomen los pedidos en orden inverso.
    FOR v_id_pedido IN
        SELECT DISTINCT id FROM unnest(v_ids) AS ids(id) ORDER BY id
    LOOP
        SELECT estado INTO v_estado
        FROM pedido
        WHERE id_pedido = v_id_pedido
        FOR SHARE;

        -- FOR SHARE bloquea también UPDATE de estado. FOR KEY SHARE no lo hacía.
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El pedido % no existe', v_id_pedido USING ERRCODE = '23503';
        END IF;

        IF v_estado <> 'PENDIENTE' THEN
            RAISE EXCEPTION 'No se puede editar el detalle del pedido % porque está %', v_id_pedido, v_estado
                USING ERRCODE = '23514';
        END IF;
    END LOOP;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_edicion_detalle_pedido ON detalle_pedido;
CREATE TRIGGER trg_validar_edicion_detalle_pedido
BEFORE INSERT OR UPDATE OR DELETE ON detalle_pedido
FOR EACH ROW
EXECUTE FUNCTION validar_edicion_detalle_pedido();

-- R3: el detalle sólo admite productos activos y una cantidad que no exceda su stock actual.
-- FOR SHARE evita que una actualización concurrente del producto cambie esa fila durante la validación.
CREATE OR REPLACE FUNCTION validar_producto_y_stock_detalle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INTEGER;
    v_activo BOOLEAN;
BEGIN
    SELECT stock, activo INTO v_stock, v_activo
    FROM producto
    WHERE id_producto = NEW.id_producto
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El producto % no existe', NEW.id_producto USING ERRCODE = '23503';
    END IF;

    IF NOT v_activo THEN
        RAISE EXCEPTION 'El producto % está inactivo', NEW.id_producto USING ERRCODE = '23514';
    END IF;

    IF NEW.cantidad > v_stock THEN
        RAISE EXCEPTION 'Stock insuficiente para el producto %: solicitado %, disponible %',
            NEW.id_producto, NEW.cantidad, v_stock USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_producto_y_stock_detalle ON detalle_pedido;
CREATE TRIGGER trg_validar_producto_y_stock_detalle
BEFORE INSERT OR UPDATE OF id_producto, cantidad ON detalle_pedido
FOR EACH ROW
EXECUTE FUNCTION validar_producto_y_stock_detalle();
