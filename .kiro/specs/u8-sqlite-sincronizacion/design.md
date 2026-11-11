# Diseño — Tablet de feria y sincronización

## Arquitectura

```text
 Tablet (SQLite)                                Servidor (PostgreSQL)
 ┌──────────────────────────┐   bajada   ┌──────────────────────────────┐
 │ snapshot, producto_cache │ ◄───────── │ sync.v_snapshot_movil (vista)│
 │ pedido_borrador          │            │                              │
 │ item_borrador            │   subida   │ sync.aplicar_solicitud(jsonb)│
 │ cola_sync (uuid)         │ ─────────► │  └─ sync.solicitud (uuid PK) │
 └──────────────────────────┘ respuesta  │  └─ tpi_registrar_pedido     │
                                         └──────────────────────────────┘
```

## Esquema local (`tpi2/u8/movil_schema.sql`)

`snapshot(version, servidor_en, descargado_en, productos > 0)`, `producto_cache(id, nombre, categoria, precio_centavos, stock_visto, disponible, eliminado, version_snapshot)`, `pedido_borrador(id_local uuid, forma_pago, creado_en, estado, id_pedido_servidor)`, `item_borrador(id_local, producto_id, cantidad > 0, precio_centavos_visto)`, `cola_sync(solicitud_uuid, id_local, estado, intentos, ..., respuesta json)`. Precios en centavos enteros. Triggers: borrador vacío no se encola; borrador enviado no se edita; solicitud resuelta no cambia. Índice único parcial: una sola solicitud `PENDIENTE` por borrador.

## Servidor (`tpi2/u8/servidor_sync.sql`)

- `sync.v_snapshot_movil`: catálogo sin datos personales, incluidos los productos dados de baja (lápidas).
- `sync.solicitud`: una fila por UUID recibido; la PK es la idempotencia. `INSERT ... ON CONFLICT DO NOTHING` hace que un reenvío concurrente espere a la primera transacción y devuelva su respuesta.
- `sync.aplicar_solicitud(jsonb)`: `SECURITY DEFINER` (dueño `fs_owner`), valida la forma, bloquea los productos con `FOR UPDATE` en orden de id, evalúa y responde.

## Política de conflictos

| Situación | Resultado | Resolución |
|---|---|---|
| Producto inexistente, dado de baja, categoría inactiva | `RECHAZADO` | Definitivo. La persona arma otro pedido |
| Cantidad mayor al stock actual | `RECHAZADO` | Definitivo; no se vende parcialmente |
| Solo cambió el precio | `CONFLICTO` | Gana el servidor: se aceptan los precios nuevos y se reenvía con otro UUID |
| Todo coincide | `APLICADO` | Pedido `CONFIRMADO`, stock descontado |
| Reenvío del mismo UUID | respuesta original, `duplicada: true` | Sin segundo pedido |
| Sin red | sigue `PENDIENTE` | Reintento posterior |

Prioridad: un solo motivo de rechazo alcanza para `RECHAZADO`, aunque además haya cambiado un precio.

## Decisiones

- **D-1 El servidor dispone.** La tablet nunca escribe tablas del servidor; solo llama a una función con permisos acotados (`rol_sync_movil`).
- **D-2 Gana el servidor en precio.** El precio vigente es una decisión comercial central; la tablet no puede imponer un precio viejo.
- **D-3 UUID nuevo al reenviar tras un conflicto.** Es otra propuesta (otros precios); reutilizar el UUID devolvería la respuesta anterior.
- **D-4 La venta de feria descuenta stock.** Se entrega en el acto. Sin esto, dos tablets podían vender la misma última unidad. La venta web conserva la regla heredada (no reserva stock), documentada como limitación.
- **D-5 Cliente genérico.** Las ventas de feria no registran comprador: se imputan a "Consumidor Final" (`sync.config`).
