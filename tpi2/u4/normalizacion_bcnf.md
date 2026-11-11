# Unidad 4 — Refactorización del esquema heredado hasta BCNF

Spec: [requirements](../../.kiro/specs/u4-migracion-legado/requirements.md) · [design](../../.kiro/specs/u4-migracion-legado/design.md) · [tasks](../../.kiro/specs/u4-migracion-legado/tasks.md). Evidencia: [`evidencias/20261110_204915/`](../evidencias/20261110_204915/) (archivos `u4_*`).

## 1. El esquema heredado

`legado.venta_planilla` es la planilla de ventas 2025 del sistema anterior: 819 renglones, 400 planillas, sin clave primaria. Cada renglón repite cliente, producto, rubro y repartidor. Los datos son sintéticos ([`01_esquema_heredado.sql`](01_esquema_heredado.sql)), pero con anomalías reales de una planilla cargada a mano:

| Anomalía | Ejemplo |
|---|---|
| Misma persona escrita de 3 formas | `CLIENTE1@EXAMPLE.TEST`, `cliente1@example.test `, `cliente1@example.test` (170 correos crudos, 118 reales) |
| Rubro mal tipeado | `Pizas` para "Pizza variedad 03" |
| Teléfono que cambió a mitad de año | 2 clientes con dos teléfonos |
| Doble carga | 10 planillas repiten un producto con otra cantidad |
| Datos obligatorios faltantes | 2 planillas sin correo |
| Mayúsculas y abreviaturas | `Transf.`/`Transferencia`, `CENTRO`/`Centro` |

Anomalías que provoca: actualizar el teléfono de un cliente exige cambiar N renglones (y si se olvida uno quedan dos teléfonos); no se puede registrar un repartidor sin una venta; borrar la última venta de un producto borra el producto.

## 2. Dependencias funcionales validadas contra los datos

No se supusieron: [`02_verificar_dependencias.sql`](02_verificar_dependencias.sql) cuenta, para cada dependencia candidata, cuántos valores del determinante aparecen con dos valores distintos del dependiente. Resultado real ([evidencia](../evidencias/20261110_204915/u4_01_dependencias_funcionales.txt)):

| # | Dependencia | Crudo | Canónico | Conclusión |
|---|---|---:|---:|---|
| 1 | `nro_planilla → fecha, cliente, forma_pago, estado, repartidor` | 0 | 0 | Cabecera del pedido |
| 2 | `email → nombre, apellido` | 0 | 0 | Cliente |
| 3 | `email → telefono` | 2 | 2 | **No se cumple** |
| 4 | `producto → rubro` | 66 | 0 | Se cumple tras canonizar y corregir `Pizas` |
| 5 | `producto → precio_unit` | 138 | 90 | **No se cumple**: el precio es de la venta |
| 6 | `(nro_planilla, producto) → precio_unit` | 0 | 0 | Precio histórico por línea |
| 7 | `(nro_planilla, producto) → cantidad` | 10 | 10 | **No se cumple**: doble carga |
| 8 | `legajo → repartidor, zona` | 6 | 0 | Se cumple tras canonizar |
| 9 | `zona → legajo` | 4 | 2 | **No se cumple**: Centro y Oeste tienen dos repartidores |

Lectura: que una dependencia se cumpla en los datos no prueba que sea una regla del negocio, pero que no se cumpla sí prueba que no puede ser clave. Las columnas "crudo" muestran por qué la normalización exige primero limpiar formato: sobre los datos crudos, la DF 4 parecía falsa (66 violaciones) y solo eran mayúsculas y un error de tipeo, corregido por una persona en `legado.correccion_rubro` (la migración no "adivina").

## 3. Formas normales

Clave candidata de la planilla (sin la doble carga): `(nro_planilla, producto)`.

- **1FN:** se cumple (valores atómicos).
- **2FN:** violada. `nro_planilla → fecha, email, forma_pago, estado, legajo` y `producto → rubro` dependen de una parte de la clave.
- **3FN:** violada. `email → nombre, apellido` y `legajo → repartidor, zona` son transitivas.
- **BCNF:** violada por todas las anteriores (sus determinantes no son superclave).

## 4. Descomposición

| Dependencia | Tabla donde el determinante es clave |
|---|---|
| `nro_planilla → fecha, forma_pago, estado, cliente` | `pedido` (PK `id_pedido`; `migracion.mapa_pedido` guarda `nro_planilla`) |
| `nro_planilla → legajo` | `entrega(id_pedido PK, repartidor_id)` |
| `email → nombre, apellido` | `cliente` (UNIQUE `correo_electronico`) |
| `producto → rubro` | `producto` (UNIQUE `nombre`, FK `categoria_id`) |
| `(planilla, producto) → precio, cantidad` | `detalle_pedido` (PK `(id_pedido, id_producto)`) |
| `legajo → nombre, zona` | `repartidor(id_repartidor PK, nombre, zona_id)` |
| `nombre_zona → id_zona` | `zona(id_zona PK, nombre UNIQUE)` |

En cada tabla resultante todo determinante no trivial es superclave: **BCNF**. La descomposición conserva las dependencias 1, 2, 4, 6 y 8 en una sola tabla cada una, y es **sin pérdida** porque cada reunión se hace por una clave (lo prueba el punto 5). Las DF que no se cumplen (3, 5, 7, 9) no se fuerzan como claves:

- **DF 3:** el cliente conserva el teléfono de su venta más reciente y el anterior queda en `migracion.discrepancia` con la regla aplicada. Si el negocio necesitara el historial de teléfonos, correspondería una tabla `telefono_cliente(id_cliente, desde, telefono)`.
- **DF 5:** el precio queda en `detalle_pedido.precio_unitario` (precio histórico), como en el modelo de la entrega anterior.
- **DF 7:** se suman las cantidades del renglón repetido (decisión: es la misma venta cargada dos veces con el mismo precio, verificado antes de sumar).
- **DF 9:** `zona` no determina repartidor; por eso la FK va de repartidor a zona y no al revés.

## 5. Migración sin pérdida, reversible

[`03_migracion.sql`](03_migracion.sql) no tiene `BEGIN` ni `COMMIT`: lo decide quien la ejecuta. Toma bloqueos (`LOCK TABLE` falla fuera de una transacción, lo que impide ejecutarla "suelta"), crea las tablas, envía a cuarentena las 2 planillas sin correo y carga el resto. [`04_verificar_migracion.sql`](04_verificar_migracion.sql) corre en la misma transacción y aborta si:

- renglones del legado ≠ migrados + cuarentena (819 = 817 + 2);
- el importe del legado ≠ importe migrado (4.488.032,00 = 4.488.032,00);
- la reconstrucción por reunión de las tablas nuevas difiere del legado canónico en cualquier fila, en cualquier sentido (`EXCEPT ALL`): **0 diferencias**;
- un cliente creado no coincide con su venta más reciente, o un rubro no se trasladó ni se registró;
- la desnormalización de la Unidad 4 quedó desincronizada.

**Plan de reversión** (probado, [huellas](../evidencias/20261110_204915/u4_05_huellas.txt)):

| Nivel | Situación | Acción | Resultado de la prueba |
|---|---|---|---|
| 0 | Antes de empezar | `pg_dump` previo | 122 KB, verificado |
| 1 | Sin confirmar | `ROLLBACK` | Huella idéntica a la inicial |
| 1 | Error a mitad de camino | Error provocado (`1/0`) tras la carga | Huella idéntica: nada quedó aplicado |
| 2 | Ya confirmada | [`05_reversion.sql`](05_reversion.sql) | Huella idéntica a la inicial |
| 3 | Base dañada | Restaurar el respaldo del nivel 0 (`tpi2/u6/restaurar.ps1`) | Procedimiento probado en la Unidad 6 |

La huella ([`tpi2/base/huella.sql`](../base/huella.sql)) es la cantidad de filas y el md5 del contenido completo de cada tabla: "idéntica" significa byte a byte. La reversión de nivel 2 se niega a ejecutarse si después de migrar alguien usó un cliente o producto creado por la migración.

**Decisión D-3, explicada.** Dos triggers del TP2 y del TPI validan *ventas nuevas* (producto activo con stock, categoría activa). Una venta de 2025 de un producto hoy discontinuado es historia válida y esos triggers la rechazarían. Se suspenden solo esos dos, dentro de la transacción (si hay `ROLLBACK`, la suspensión también se revierte) y se verifica al final que ningún trigger quedó deshabilitado. El resto de las reglas siguen activas.

## 6. Desnormalización controlada

| Desnormalización | Cuándo | Por qué | Salvaguarda |
|---|---|---|---|
| `unidad4.ventas_categoria_diaria` (materializada) — Unidad 4 | Reporte "top 5 categorías del día" | Lectura de 114 ms → 0,04 ms (medido en [tpUnidad4](../../tpUnidad4/README.md)) | Triggers por sentencia la reconstruyen en la misma transacción; `unidad4.auditoria_ventas` compara contra la fuente en ambos sentidos: **0 filas** tras migrar 817 renglones. Costo: escrituras más lentas (refresh completo) |
| `tp5_facturacion_mensual` (materializada) — TP5 | Reporte mensual | 217 ms → 0,02 ms | `REFRESH CONCURRENTLY` semanal en el plan de mantenimiento; puede estar atrasada hasta el refresco |
| `anon.*` (materializadas) — Unidad 5 | Datos para reportes e IA | Quien las lee no necesita permiso sobre las tablas reales | `seguridad.v_equivalencia_usuario` detecta si quedaron viejas; refresco semanal |
| `pedidos` en MongoDB — Unidad 7 | Lectura de pedido completo | Una lectura sin JOIN | Se regenera desde PostgreSQL; validador exige total = suma de líneas |
| `detalle_pedido.precio_unitario` | Siempre | No es redundancia: es el precio *de la venta* (DF 5 no se cumple) | — |

Lo que se decidió **no** desnormalizar: guardar el total en `pedido` (se calcula con `tpi_total_pedido`; un total guardado podría contradecir sus líneas) ni el nombre del repartidor en `entrega`.
