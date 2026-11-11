# Diseño — Migración de la planilla heredada a BCNF

## Fuente

`legado.venta_planilla(nro_planilla, renglon, fecha_txt, cliente_email, cliente_nombre, cliente_apellido, cliente_telefono, producto, rubro, precio_unit, cantidad, medio_pago, estado, repartidor_legajo, repartidor_nombre, zona)`.

La vista `legado.v_venta_canonica` elimina diferencias de formato que no son diferencias de dato (mayúsculas, espacios, `Transf.` = `TRANSFERENCIA`) y aplica únicamente las correcciones aprobadas por una persona en `legado.correccion_rubro`.

## Dependencias funcionales (resultado de la validación)

| # | Dependencia | Violaciones crudo → canónico | Decisión |
|---|---|---|---|
| 1 | `nro_planilla → fecha, cliente, forma_pago, estado, repartidor` | 0 → 0 | Se cumple: cabecera = `pedido` (+ `entrega`) |
| 2 | `email → nombre, apellido` | 0 → 0 | Se cumple: `cliente` |
| 3 | `email → telefono` | 2 → 2 | **No se cumple**: el teléfono cambió en el tiempo. Se conserva el más reciente; los anteriores van a `migracion.discrepancia` |
| 4 | `producto → rubro` | 66 → 0 | Se cumple tras canonizar y corregir `Pizas`: `producto.categoria_id` |
| 5 | `producto → precio_unit` | 138 → 90 | **No se cumple**: el precio es de la venta, no del producto. Queda en `detalle_pedido.precio_unitario` |
| 6 | `(nro_planilla, producto) → precio_unit` | 0 → 0 | Se cumple: precio histórico por línea |
| 7 | `(nro_planilla, producto) → cantidad` | 10 → 10 | **No se cumple**: doble carga. Se suman cantidades (la PK es `(pedido, producto)`) |
| 8 | `legajo → repartidor, zona` | 6 → 0 | Se cumple tras canonizar: `repartidor(id_repartidor, nombre, zona_id)` |
| 9 | `zona → legajo` | 4 → 2 | **No se cumple**: una zona tiene varios repartidores. No es clave |

## Esquema destino (BCNF)

Tablas existentes, sin cambios: `cliente`, `categoria`, `producto`, `pedido`, `detalle_pedido`. Tablas nuevas:

- `zona(id_zona PK, nombre UNIQUE)`
- `repartidor(id_repartidor PK, nombre, zona_id FK)` — `id_repartidor` es el legajo.
- `entrega(id_pedido PK FK, repartidor_id FK)` — un pedido tiene a lo sumo una entrega; las anuladas no tienen.

En cada tabla los únicos determinantes no triviales son sus claves (ver `tpi2/u4/normalizacion_bcnf.md`).

## Decisiones

- **D-1 Grafía.** Correos en minúsculas; productos y categorías se emparejan sin distinguir mayúsculas. Lo que ya existe en el catálogo vigente manda.
- **D-2 Datos solo del legado.** Productos y categorías que no existen se crean **inactivos** y sin stock: son historia, no catálogo.
- **D-3 Triggers de venta nueva.** Durante la carga histórica se suspenden solo `trg_validar_producto_y_stock_detalle` y `trg_tpi_categorias_insert` (describen ventas nuevas, no historia). PK, FK, CHECK, la regla "solo pedidos PENDIENTE" y la sincronización de la Unidad 4 siguen activas. La suspensión es transaccional y se verifica que todo trigger quede habilitado.
- **D-4 Estados.** Los pedidos nacen `PENDIENTE` y pasan por las transiciones permitidas (`PENDIENTE → CONFIRMADO → ENTREGADO`, `PENDIENTE → CANCELADO`).
- **D-5 Trazabilidad.** `migracion.mapa_*` relaciona cada valor del legado con su fila nueva e indica si fue creada por la migración. La reversión usa esos mapas.

## Verificación sin pérdida

`04_verificar_migracion.sql` compara `migracion.v_legado_esperado` (legado canónico, sin cuarentena, con la doble carga sumada) contra `migracion.v_reconstruccion` (reunión de `pedido`, `cliente`, `detalle_pedido`, `producto`, `entrega`, `repartidor`, `zona`) con `EXCEPT ALL` en ambos sentidos. Además controla conteos, importe total, clientes creados, rubros y la auditoría de la Unidad 4.

## Reversión

| Nivel | Cuándo | Cómo |
|---|---|---|
| 1 | Antes de confirmar | `ROLLBACK` (el DDL de PostgreSQL es transaccional) |
| 2 | Confirmada, sin uso posterior | `05_reversion.sql` en una transacción |
| 3 | Base dañada | Restaurar el `pg_dump` previo con `tpi2/u6/restaurar.ps1` |

La prueba compara una huella de contenido (`tpi2/base/huella.sql`: filas y md5 por tabla) antes y después de cada nivel.
