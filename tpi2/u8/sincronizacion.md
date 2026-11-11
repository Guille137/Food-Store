# Unidad 8 — Tablet de feria: SQLite y sincronización con PostgreSQL

Spec: [requirements](../../.kiro/specs/u8-sqlite-sincronizacion/requirements.md) · [design](../../.kiro/specs/u8-sqlite-sincronizacion/design.md) · [tasks](../../.kiro/specs/u8-sqlite-sincronizacion/tasks.md). Evidencia: archivos `u8_*` y [`u8_tablets/`](../evidencias/20261110_204915/u8_tablets/) (volcado SQL de cada base local).

## Piezas

| Archivo | Lado | Qué hace |
|---|---|---|
| [`movil_schema.sql`](movil_schema.sql) | SQLite | 5 tablas `STRICT`, FK, `CHECK`, triggers y vista de catálogo |
| [`cliente_movil.py`](cliente_movil.py) | Tablet | Descarga del catálogo, borradores, cola, envío, reintento y resolución de conflictos |
| [`servidor_sync.sql`](servidor_sync.sql) | PostgreSQL | `sync.v_snapshot_movil`, `sync.solicitud`, `sync.aplicar_solicitud(jsonb)` |
| [`../u5/04_roles.sql`](../u5/04_roles.sql) | PostgreSQL | `rol_sync_movil`: solo leer la instantánea y ejecutar la función |

## Casos probados

Resultado de la corrida ([casos](../evidencias/20261110_204915/u8_01_casos_sincronizacion.txt), [estado del servidor](../evidencias/20261110_204915/u8_03_estado_servidor.txt)):

| Caso | Situación | Resultado |
|---|---|---|
| C0 | ¿La instantánea lleva datos personales? | No: id, nombre, categoría, precio en centavos, stock, disponible, eliminado |
| C1 | Servidor caído | La descarga falla; el catálogo local sigue consultable |
| C2 | El precio subió en el servidor después de copiar el catálogo | `CONFLICTO` con precio visto y actual. Se baja catálogo nuevo, se acepta el precio y se reenvía con otro UUID → `APLICADO` al precio nuevo |
| C3 | Cantidad mayor que el stock | `RECHAZADO` (`STOCK_INSUFICIENTE`), stock sin cambios |
| C4 | Producto dado de baja después de copiar el catálogo | `RECHAZADO` (`PRODUCTO_DADO_DE_BAJA`). En la tablet queda como lápida: oculto del catálogo, fila conservada para el borrador viejo |
| C5 | Todo coincide | `APLICADO`: pedido `CONFIRMADO` en PostgreSQL y stock descontado |
| C6 | El servidor aplicó pero la respuesta se perdió | La tablet reenvía el **mismo** UUID: el servidor responde `duplicada: true` con el mismo pedido. 2 envíos, 1 venta |
| C7 | Sincronizar sin red | La primera solicitud falla por red, la sincronización se detiene, las 4 quedan `PENDIENTE`; al volver la red se envían todas |
| C8 | Dos tablets piden 2 unidades cuando quedan 3 | `tablet-01` `APLICADO`; `tablet-02` espera el bloqueo (`FOR UPDATE`) y queda `RECHAZADO`. Stock final 1, nunca negativo |
| C9 | Borrador sin ítems | No se puede encolar (trigger) |
| C10 | Instantánea vacía | Rechazada; se conserva el catálogo anterior |
| C11 | Datos inválidos | SQLite rechaza 5 de 5: cantidad 0, producto inexistente, UUID mal formado, forma de pago inexistente, texto en columna entera |
| — | ¿La tablet puede registrar un pedido sin pasar por la sincronización? | No: `permission denied for schema public` |
| — | Integridad | `PRAGMA integrity_check = ok` y `foreign_key_check` vacío en ambas tablets; en el servidor, cada solicitud aplicada tiene exactamente un pedido y ninguna quedó `EN_PROCESO` |

## Cómo se resuelve cada conflicto (y por qué)

- **Rechazo** (baja, categoría inactiva, sin stock, inexistente): es definitivo, porque el servidor es la fuente de verdad del catálogo. No se vende parcialmente: la persona decide qué hacer con el cliente que tiene enfrente.
- **Precio cambiado:** gana el servidor. La tablet no puede imponer un precio viejo; la persona confirma el precio nuevo y se envía una solicitud **nueva**. Reutilizar el UUID devolvería la respuesta anterior (eso es la idempotencia, C6).
- **Concurrencia entre tablets:** la serializa PostgreSQL. `sync.aplicar_solicitud` bloquea los productos con `FOR UPDATE` en orden de id (evita interbloqueos) y descuenta el stock en la misma transacción.

## Correcciones respecto de TP8

La revisión de código de [`tp8/`](../../tp8/) había encontrado defectos que se aceptaron pero no se corrigieron. Esta versión los corrige y los prueba:

| Defecto de TP8 | Corrección | Caso |
|---|---|---|
| Una solicitud sin ítems quedaba `SIMULADO_APROBADO` | Trigger: un borrador vacío no se encola; el servidor además rechaza `items` vacío | C9 |
| Un borrador podía tener dos solicitudes pendientes | Índice único parcial | — |
| Una instantánea vacía marcaba todo el catálogo como baja | `CHECK (productos > 0)` y rechazo en el cliente | C10 |
| `snapshot_postgresql.sql` no exportaba la columna `stock` que la tabla SQLite exigía | La vista nueva la incluye | C3, C8 |
| La "sincronización" no llegaba al servidor (solo comparaba con un CSV) | Función de servidor con idempotencia y pedidos reales | C2–C8 |
