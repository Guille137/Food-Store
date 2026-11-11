# Unidad 7 — Solución documental vs. relacional

Spec: [requirements](../../.kiro/specs/u7-modelo-documental/requirements.md) · [design](../../.kiro/specs/u7-modelo-documental/design.md) · [tasks](../../.kiro/specs/u7-modelo-documental/tasks.md). Motores: PostgreSQL 17.11 y MongoDB 8.0.15. Evidencia: archivos `u7_*` de [`evidencias/20261110_204915/`](../evidencias/20261110_204915/).

## Datos

Los 2.398 pedidos con líneas de la base del proyecto (2.000 originales + 398 migrados del legado en la Unidad 4), exportados por [`01_exportar_pedidos.sql`](01_exportar_pedidos.sql) y cargados en la colección `pedidos` con validador. La carga aceptó los 2.398 documentos; no hay datos de ejemplo escritos a mano. La entrega anterior ([`unidad 7/`](../../unidad%207/)) trabajaba con 5 pedidos tipeados en el script.

## Resultados: ¿dicen lo mismo?

Las ocho consultas se escribieron dos veces ([MongoDB](04_consultas.js), [SQL](05_consultas.sql)) con el mismo formato de salida y `tpi2/ejecutar_todo.py` compara los resultados completos, no solo los conteos:

| Consulta | ¿Idénticos? | PostgreSQL (ms) | MongoDB (ms) | Plan MongoDB |
|---|:---:|---:|---:|---|
| C1 Pedido completo por id | Sí | 0,39 | 1,75 | `EXPRESS_IXSCAN(_id_)`, 1 doc |
| C2 Pedidos por estado | Sí | 3,01 | 3,78 | `COLLSCAN`, 2.398 docs |
| C3 Pedidos que contienen un producto | Sí | 0,18 | 2,64 | `IXSCAN(lineas_producto)` multiclave, 76 docs |
| C4 Entregados con total > $20.000 | Sí | 6,61 | 10,56 | `IXSCAN(estado_fecha)`, 1.785 docs |
| C5 Facturación por categoría y mes (`$unwind`) | Sí | 13,47 | 20,39 | `IXSCAN(estado_fecha)`, 1.785 docs |
| C6 Top 5 clientes | Sí | 6,26 | 7,04 | `IXSCAN(estado_fecha)` |
| C7 Historial de un cliente | Sí | 0,43 | 1,78 | `IXSCAN(cliente_fecha)`, 12 docs |
| C8 Ticket promedio por forma de pago | Sí | 6,72 | 7,03 | `IXSCAN(estado_fecha)` |

Medianas de 30 ejecuciones, medidas **dentro de cada motor** (sin red ni arranque del cliente), con caché caliente, en una notebook. Con 2.398 pedidos todas las diferencias están por debajo de los 10 ms: el volumen no permite concluir nada sobre rendimiento a escala, y no se presenta como un benchmark. Lo que sí muestran los planes es que cada consulta MongoDB usa el índice previsto (salvo C2, que agrupa toda la colección).

## Integridad: qué garantiza cada motor

| Regla | PostgreSQL | MongoDB |
|---|---|---|
| Estado y forma de pago válidos | `ENUM` | Validador `enum` ✔ |
| Cantidad > 0, precio ≥ 0 | `CHECK` | Validador ✔ |
| Total = suma de líneas | No se guarda: se calcula | Validador `$expr` ✔ |
| Un producto una sola vez por pedido | PK `(id_pedido, id_producto)` | Validador `$setUnion` ✔ |
| Importes exactos | `NUMERIC(10,2)` | `Decimal128` (un `double` es rechazado) ✔ |
| El cliente existe | FK | ✘ No se puede garantizar al escribir |
| El producto existe y está activo | FK + trigger | ✘ No se puede garantizar |
| Transición de estados válida | Trigger | ✘ |
| Transacción de varias tablas | Sí | Sí, pero acá no hace falta: el pedido es un solo documento |

Pruebas del validador ([evidencia](../evidencias/20261110_204915/u7_05_validador_y_duplicacion.json)): el documento de control se acepta; se rechazan total incorrecto, cantidad 0, estado inexistente, importe `double`, campo no previsto (correo del cliente), pedido sin líneas y producto repetido; el `_id` repetido da `E11000`.

## Duplicación

Corregir el apellido de un cliente en PostgreSQL es `UPDATE` de **1** fila. En MongoDB hay que modificar **10** documentos (todos sus pedidos) y, si el proceso se corta a mitad, quedan pedidos con dos apellidos distintos. Para nombre, categoría y precio del producto la duplicación es intencional: son la foto de la venta y **no** deben cambiar si cambia el catálogo.

## Decisión

**PostgreSQL sigue siendo la base del sistema** (fuente de verdad de catálogo, stock, clientes y pedidos), por tres razones verificadas en este trabajo:

1. Las reglas que más importan al negocio —el cliente y el producto existen, el producto está activo, hay stock, las transiciones de estado son válidas— son integridad referencial y entre entidades. MongoDB no puede garantizarlas al escribir (tabla anterior).
2. Las escrituras del negocio tocan varias entidades a la vez (pedido + líneas + stock + auditoría) y ya están resueltas con procedimientos transaccionales probados en las unidades anteriores.
3. Con este volumen no hay ventaja de rendimiento que compense: PostgreSQL resuelve el pedido completo con tres JOIN en 0,39 ms.

**MongoDB queda como vista de lectura derivada**, justificada solo si aparece la necesidad concreta: muchos lectores del "pedido completo" (por ejemplo, una app de seguimiento para clientes) que no deben cargar la base transaccional. En ese caso la colección se regenera desde PostgreSQL con [`01_exportar_pedidos.sql`](01_exportar_pedidos.sql), nunca se escribe directamente, y el validador protege lo que puede.

## Contraste con lo que propuso la IA

| Propuesta | Decisión |
|---|---|
| Guardar los importes como números de JavaScript (`double`), como hacía el script de la entrega anterior (generado con Codex) | **Descartada:** errores de redondeo en sumas de dinero. Se usa `Decimal128` y el validador rechaza `double` |
| Embeber el correo del cliente, como en la entrega anterior | **Descartada:** minimización de datos personales; el caso de uso no lo necesita. El validador rechaza el campo |
| "Al embeber ya no hace falta validar" (afirmación ya refutada en la entrega anterior) | **Refutada otra vez con evidencia:** sin `$expr`, un total incorrecto se aceptaría |
| Comparar solo la cantidad de resultados | **Ampliada:** se comparan los resultados completos, valor por valor |
