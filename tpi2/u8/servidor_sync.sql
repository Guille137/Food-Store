-- Unidad 8 · Lado servidor de la sincronización móvil (PostgreSQL).
-- Spec: .kiro/specs/u8-sqlite-sincronizacion/.
-- Principio: "la tablet propone, el servidor dispone". La tablet solo puede
--   (a) leer la instantánea del catálogo (sin clientes ni datos personales) y
--   (b) proponer un pedido llamando a sync.aplicar_solicitud().
-- No tiene acceso directo a ninguna tabla.
-- Ejecutar dentro de una transacción externa, ANTES de tpi2/u5/04_roles.sql
-- (que asigna dueño y permisos de este esquema).

CREATE SCHEMA sync;

-- Las ventas de feria no registran datos del comprador: se imputan a un
-- cliente genérico, creado acá, para respetar la FK pedido -> cliente.
INSERT INTO public.cliente (correo_electronico, nombre, apellido)
VALUES ('ventas.feria@foodstore.example', 'Consumidor', 'Final');

CREATE TABLE sync.config (
    unica            boolean PRIMARY KEY DEFAULT TRUE CHECK (unica),
    id_cliente_feria integer NOT NULL REFERENCES public.cliente
);
INSERT INTO sync.config (id_cliente_feria)
SELECT id_cliente FROM public.cliente WHERE correo_electronico = 'ventas.feria@foodstore.example';

-- Instantánea que baja a la tablet. Los productos dados de baja siguen
-- saliendo (como lápidas) para que la tablet pueda rechazar borradores viejos.
-- Corrige el defecto hallado en tp8/servidor/snapshot_postgresql.sql, donde
-- faltaba la columna stock.
CREATE VIEW sync.v_snapshot_movil AS
SELECT p.id_producto AS id,
       p.nombre,
       c.nombre AS categoria,
       (p.precio_lista * 100)::bigint AS precio_centavos,
       p.stock,
       (p.activo AND c.activo) AS disponible,
       (NOT p.activo) AS eliminado
FROM public.producto AS p
JOIN public.categoria AS c ON c.id_categoria = p.categoria_id;

-- Una fila por solicitud recibida. La clave primaria ES la idempotencia: la
-- misma solicitud reenviada no puede crear un segundo pedido.
CREATE TABLE sync.solicitud (
    solicitud_uuid uuid PRIMARY KEY,
    dispositivo    text NOT NULL,
    recibida_en    timestamptz NOT NULL DEFAULT clock_timestamp(),
    rol_sesion     text NOT NULL DEFAULT session_user,
    estado         text NOT NULL CHECK (estado IN ('EN_PROCESO', 'APLICADO', 'CONFLICTO', 'RECHAZADO')),
    id_pedido      integer REFERENCES public.pedido,
    pedido         jsonb NOT NULL,       -- lo que la tablet propuso
    respuesta      jsonb,                -- lo que el servidor contestó
    CONSTRAINT chk_solicitud_aplicada CHECK ((estado = 'APLICADO') = (id_pedido IS NOT NULL))
);
CREATE INDEX idx_solicitud_estado ON sync.solicitud (estado, recibida_en);

-- Entrada: {"solicitud_uuid": "...", "dispositivo": "tablet-01", "forma_pago": "EFECTIVO",
--           "items": [{"producto_id": 1, "cantidad": 2, "precio_centavos_visto": 100000}]}
-- Salida:  {"estado": "APLICADO|CONFLICTO|RECHAZADO", "id_pedido": n|null,
--           "duplicada": bool, "problemas": [{"producto_id", "motivo", ...}]}
-- Prioridad: un solo motivo de rechazo alcanza para RECHAZADO; si no hay
-- rechazos pero cambió algún precio es CONFLICTO; si no, se aplica.
CREATE FUNCTION sync.aplicar_solicitud(p_solicitud jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_uuid       uuid;
    v_items      jsonb := p_solicitud -> 'items';
    v_item       jsonb;
    v_prod       record;
    v_problemas  jsonb := '[]'::jsonb;
    v_rechazo    boolean := FALSE;
    v_conflicto  boolean := FALSE;
    v_estado     text;
    v_id_pedido  integer;
    v_lineas     jsonb;
    v_respuesta  jsonb;
    v_cliente    integer;
    v_forma_pago public.forma_pago;
BEGIN
    -- 1. Forma de la solicitud. Un pedido vacío no se acepta (defecto detectado
    --    en la revisión de TP8, donde una solicitud sin ítems quedaba aprobada).
    IF jsonb_typeof(p_solicitud) IS DISTINCT FROM 'object'
       OR (p_solicitud ->> 'solicitud_uuid') IS NULL
       OR COALESCE(btrim(p_solicitud ->> 'dispositivo'), '') = ''
       OR jsonb_typeof(v_items) IS DISTINCT FROM 'array'
       OR jsonb_array_length(v_items) = 0
       OR (p_solicitud ->> 'forma_pago') IS NULL
       OR (p_solicitud ->> 'forma_pago') NOT IN ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA') THEN
        RAISE EXCEPTION 'Solicitud mal formada: se requieren solicitud_uuid, dispositivo, forma_pago válida e items no vacío'
            USING ERRCODE = '22023';
    END IF;
    v_uuid := (p_solicitud ->> 'solicitud_uuid')::uuid;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_items) AS e
               WHERE jsonb_typeof(e -> 'producto_id') IS DISTINCT FROM 'number'
                  OR jsonb_typeof(e -> 'cantidad') IS DISTINCT FROM 'number'
                  OR jsonb_typeof(e -> 'precio_centavos_visto') IS DISTINCT FROM 'number'
                  OR (e ->> 'producto_id') !~ '^[1-9][0-9]{0,8}$'
                  OR (e ->> 'cantidad') !~ '^[1-9][0-9]{0,5}$'
                  OR (e ->> 'precio_centavos_visto') !~ '^[0-9]{1,12}$')
       OR (SELECT count(DISTINCT e ->> 'producto_id') FROM jsonb_array_elements(v_items) AS e)
          <> jsonb_array_length(v_items) THEN
        RAISE EXCEPTION 'Ítems inválidos: enteros positivos y sin productos repetidos'
            USING ERRCODE = '22023';
    END IF;

    -- 2. Idempotencia. Si otra transacción está procesando el mismo UUID, este
    --    INSERT espera a que termine y luego no inserta nada.
    INSERT INTO sync.solicitud (solicitud_uuid, dispositivo, estado, pedido)
    VALUES (v_uuid, btrim(p_solicitud ->> 'dispositivo'), 'EN_PROCESO', p_solicitud)
    ON CONFLICT (solicitud_uuid) DO NOTHING;
    IF NOT FOUND THEN
        SELECT respuesta || jsonb_build_object('duplicada', TRUE) INTO v_respuesta
        FROM sync.solicitud WHERE solicitud_uuid = v_uuid;
        RETURN v_respuesta;
    END IF;

    -- 3. Comparar lo que la tablet vio con el estado actual. Se bloquean los
    --    productos con FOR UPDATE, en orden de id (evita interbloqueos): si dos
    --    tablets piden las últimas unidades a la vez, la segunda espera y luego
    --    ve el stock ya descontado por la primera.
    FOR v_item IN SELECT e FROM jsonb_array_elements(v_items) AS e
                  ORDER BY (e ->> 'producto_id')::integer LOOP
        SELECT p.id_producto, p.precio_lista, p.stock, p.activo, c.activo AS categoria_activa
        INTO v_prod
        FROM public.producto AS p JOIN public.categoria AS c ON c.id_categoria = p.categoria_id
        WHERE p.id_producto = (v_item ->> 'producto_id')::integer
        FOR UPDATE OF p;

        IF NOT FOUND THEN
            v_rechazo := TRUE;
            v_problemas := v_problemas || jsonb_build_object(
                'producto_id', (v_item ->> 'producto_id')::integer, 'motivo', 'PRODUCTO_INEXISTENTE');
        ELSIF NOT v_prod.activo THEN
            v_rechazo := TRUE;
            v_problemas := v_problemas || jsonb_build_object(
                'producto_id', v_prod.id_producto, 'motivo', 'PRODUCTO_DADO_DE_BAJA');
        ELSIF NOT v_prod.categoria_activa THEN
            v_rechazo := TRUE;
            v_problemas := v_problemas || jsonb_build_object(
                'producto_id', v_prod.id_producto, 'motivo', 'CATEGORIA_INACTIVA');
        ELSIF (v_item ->> 'cantidad')::integer > v_prod.stock THEN
            v_rechazo := TRUE;
            v_problemas := v_problemas || jsonb_build_object(
                'producto_id', v_prod.id_producto, 'motivo', 'STOCK_INSUFICIENTE',
                'pedido', (v_item ->> 'cantidad')::integer, 'stock_actual', v_prod.stock);
        ELSIF (v_item ->> 'precio_centavos_visto')::bigint <> (v_prod.precio_lista * 100)::bigint THEN
            v_conflicto := TRUE;
            v_problemas := v_problemas || jsonb_build_object(
                'producto_id', v_prod.id_producto, 'motivo', 'PRECIO_CAMBIADO',
                'precio_centavos_visto', (v_item ->> 'precio_centavos_visto')::bigint,
                'precio_centavos_actual', (v_prod.precio_lista * 100)::bigint);
        END IF;
    END LOOP;

    -- 4. Resolver.
    IF v_rechazo THEN
        v_estado := 'RECHAZADO';
    ELSIF v_conflicto THEN
        v_estado := 'CONFLICTO';
    ELSE
        v_estado := 'APLICADO';
        SELECT jsonb_agg(jsonb_build_object('id_producto', (e ->> 'producto_id')::integer,
                                            'cantidad', (e ->> 'cantidad')::integer))
        INTO v_lineas FROM jsonb_array_elements(v_items) AS e;
        -- Reutiliza el procedimiento del TPI: mismas reglas que una venta web.
        -- (CALL no admite subconsultas como argumento: se leen antes.)
        SELECT id_cliente_feria INTO v_cliente FROM sync.config;
        v_forma_pago := (p_solicitud ->> 'forma_pago')::public.forma_pago;
        CALL public.tpi_registrar_pedido(v_cliente, v_forma_pago, v_lineas, v_id_pedido);
        UPDATE public.pedido SET estado = 'CONFIRMADO' WHERE id_pedido = v_id_pedido;
        -- La venta de feria se entrega en el acto: descuenta stock (los productos
        -- ya están bloqueados por esta transacción). Decisión D-4 de la spec U8.
        UPDATE public.producto AS p SET stock = p.stock - (e ->> 'cantidad')::integer
        FROM jsonb_array_elements(v_items) AS e
        WHERE p.id_producto = (e ->> 'producto_id')::integer;
    END IF;

    v_respuesta := jsonb_build_object('estado', v_estado, 'id_pedido', v_id_pedido,
                                      'duplicada', FALSE, 'problemas', v_problemas);
    UPDATE sync.solicitud
    SET estado = v_estado, id_pedido = v_id_pedido, respuesta = v_respuesta
    WHERE solicitud_uuid = v_uuid;
    RETURN v_respuesta;
END;
$$;

SELECT count(*) AS productos_en_instantanea,
       count(*) FILTER (WHERE disponible) AS disponibles,
       count(*) FILTER (WHERE eliminado) AS lapidas
FROM sync.v_snapshot_movil;
