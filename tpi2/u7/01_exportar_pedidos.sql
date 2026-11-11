-- Unidad 7 · Exporta los pedidos de PostgreSQL como documentos JSON (uno por línea).
-- Es la "migración" hacia MongoDB: cada documento es un pedido completo con sus
-- líneas embebidas. Uso (lo hace tpi2/ejecutar_todo.py):
--   psql -X -At -d BASE -f tpi2/u7/01_exportar_pedidos.sql -o pedidos.ndjson
--
-- Decisiones del modelo documental (ver tpi2/u7/comparacion_documental_relacional.md):
--  * Se embebe la línea completa (producto, categoría, precio histórico y cantidad):
--    es una foto de la venta y no cambia aunque cambie el catálogo.
--  * Del cliente se embeben solo id, nombre y apellido. Correo y teléfono NO viajan
--    (minimización de datos personales: el caso de uso no los necesita).
--  * Los importes viajan como texto y se cargan como Decimal128 (nunca como double).
--  * El total se guarda (dato derivado) y el validador de la colección exige que
--    coincida con la suma de las líneas.
SELECT json_build_object(
    '_id', p.id_pedido,
    'fecha', to_char(p.fecha AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'estado', p.estado,
    'forma_pago', p.forma_pago,
    'cliente', json_build_object('id_cliente', c.id_cliente, 'nombre', c.nombre, 'apellido', c.apellido),
    'lineas', l.lineas,
    'total', l.total::text,
    'cantidad_items', l.items
)::text
FROM public.pedido AS p
JOIN public.cliente AS c ON c.id_cliente = p.cliente_id
JOIN LATERAL (
    SELECT json_agg(json_build_object(
               'id_producto', d.id_producto,
               'producto', pr.nombre,
               'categoria', cat.nombre,
               'cantidad', d.cantidad,
               'precio_unitario', d.precio_unitario::text,
               'subtotal', (d.cantidad * d.precio_unitario)::text)
           ORDER BY d.id_producto) AS lineas,
           sum(d.cantidad * d.precio_unitario) AS total,
           sum(d.cantidad) AS items
    FROM public.detalle_pedido AS d
    JOIN public.producto AS pr ON pr.id_producto = d.id_producto
    JOIN public.categoria AS cat ON cat.id_categoria = pr.categoria_id
    WHERE d.id_pedido = p.id_pedido
) AS l ON TRUE
WHERE l.lineas IS NOT NULL          -- un pedido sin líneas no es una venta
ORDER BY p.id_pedido;
