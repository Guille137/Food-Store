-- Ejecutar en SQLite después de importar una instantánea nueva a snapshot_servidor.
-- Solo lee la copia local. Las solicitudes resueltas dejan de estar PENDIENTE,
-- por lo que volver a ejecutar este archivo no las evalúa ni duplica resultados.

UPDATE cola_sync AS q
SET estado = CASE
        WHEN EXISTS (
            SELECT 1
            FROM item_borrador AS i
            LEFT JOIN snapshot_servidor AS s ON s.id = i.producto_id
            WHERE i.id_local = q.id_local
              AND (s.id IS NULL OR s.disponible <> 't' OR s.eliminado = 't'
                   OR i.cantidad > CAST(s.stock AS INTEGER))
        ) THEN 'RECHAZADO'
        WHEN EXISTS (
            SELECT 1
            FROM item_borrador AS i
            JOIN snapshot_servidor AS s ON s.id = i.producto_id
            WHERE i.id_local = q.id_local
              AND i.precio_centavos_visto <> CAST(s.precio_centavos AS INTEGER)
        ) THEN 'CONFLICTO'
        ELSE 'SIMULADO_APROBADO'
    END,
    motivo = CASE
        WHEN EXISTS (
            SELECT 1
            FROM item_borrador AS i
            LEFT JOIN snapshot_servidor AS s ON s.id = i.producto_id
            WHERE i.id_local = q.id_local
              AND (s.id IS NULL OR s.disponible <> 't' OR s.eliminado = 't'
                   OR i.cantidad > CAST(s.stock AS INTEGER))
        ) THEN 'Producto inexistente, no disponible, dado de baja o stock insuficiente'
        WHEN EXISTS (
            SELECT 1
            FROM item_borrador AS i
            JOIN snapshot_servidor AS s ON s.id = i.producto_id
            WHERE i.id_local = q.id_local
              AND i.precio_centavos_visto <> CAST(s.precio_centavos AS INTEGER)
        ) THEN 'El precio cambió desde la copia del catálogo'
        ELSE 'Datos coinciden con la instantánea; no es una venta'
    END
WHERE q.estado = 'PENDIENTE';

SELECT solicitud_uuid, id_local, estado, motivo
FROM cola_sync
ORDER BY solicitud_uuid;
