# Parte 1 — Reportes analíticos y optimización

## Modelo y protocolo

Se continúa el proyecto Food Store del TP3, sin eliminar sus índices. Se creó una copia nueva `food_store_tp4_20260922_151803` desde `food_store_tp3_20260922_142245_trabajo`. PostgreSQL 17.11 sobre Windows; zona de sesión UTC; 50.003 productos, 20.001 clientes, 200.003 pedidos y 600.000 detalles. El índice docente idx_pedido_usuario corresponde a idx_pedido_cliente en este modelo.

La especificación está en [spec_analiticas.md](spec_analiticas.md). A1 combina cuatro tablas y A2 tres. Las consultas se versionan aquí porque los reportes se adaptan a las columnas del proyecto: los importes se calculan desde el detalle, sin inventar pedido.total ni marcas de eliminación inexistentes.

Se verificó current_database/current_user/version, se guardó un dump inicial, se ejecutó VACUUM (ANALYZE) y se midió antes de proponer cambios. Antes del DDL se respaldó la copia otra vez; los CREATE INDEX se ensayaron con ROLLBACK y luego se confirmaron. El ejecutor guarda los mensajes reales CREATE INDEX. Las pruebas de casos límite se revirtieron completamente. Los dumps se conservan fuera de Git en backups; no se afirma haber probado su restauración.

## Tabla comparativa — estrategias elegidas

| Consulta | Algoritmos antes | Cambio aceptado | Algoritmos después | Antes (ms) | Después (ms) | Mejora |
|---|---|---|---|---:|---:|---:|
| A1 | Merge Join; Nested Loop; Nested Loop | Índices nuevos; SQL original | Merge Join; Nested Loop; Nested Loop | 89.276 | 64.069 | 1.39× |
| A2 | Hash Join; Parallel Hash Join | Índices y agregado por cliente antes de unir nombres | Hash Join; Parallel Hash Join | 186.607 | 145.723 | 1.28× |

Los tiempos son medianas de cinco EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON), después de un calentamiento idéntico. Cost no son milisegundos. Los TXT son una ejecución adicional para lectura humana, por lo que su Execution Time puede diferir de la mediana. Se conservan todas las muestras y la variación observada; la comparación describe esta máquina y datos con caché caliente, no garantiza igual rendimiento en otra carga.

## SQL elegido y candidato descartado

- **A1 final:** [a1_antes.sql](a1_antes.sql) con [indices.sql](indices.sql). Se mantiene el SQL porque los índices por sí solos bajaron la mediana de 89.276 a 64.069 ms. Pedido pasa de Parallel Seq Scan a Parallel Index Only Scan sobre pedidos entregados; las búsquedas de detalle pasan a Index Only Scan. Permanecen los dos Nested Loop y el Merge Join con categoría.
- **A1 descartado:** [a1_despues.sql](a1_despues.sql) conserva la propuesta de rango UTC. Su mediana fue 98.570 ms, peor que la base y que el SQL original con índices. Cambió a tres Hash Join, construyó hashes de pedido, producto y categoría y recorrió detalle_pedido en paralelo. El rango mejoró las estimaciones de pedidos y redujo accesos a buffers, pero el plan completo no fue más rápido: no se acepta solo por parecer más indexable ni por tener menos shared hits.
- **A2 final:** [a2_despues.sql](a2_despues.sql) con los índices. La agregación por cliente ocurre antes del Hash Join con cliente; ese join recibe 5.000 grupos en lugar de las líneas de pedidos. El join pedido–detalle sigue siendo Parallel Hash Join. No se inventa un cambio de algoritmo: cambia la ubicación del agregado y el volumen transportado.

El índice parcial de pedido ocupa 1,589,248 bytes y el índice de detalle cubierto 24,346,624 bytes. Las futuras escrituras deberán mantenerlos; este ensayo no mide el costo de INSERT/UPDATE.

## Todas las mediciones, incluidos los intentos no elegidos

| Etapa | Cinco Execution Time (ms) | Mediana (ms) |
|---|---|---:|
| a1_antes | 157.910, 75.464, 76.675, 143.146, 89.276 | 89.276 |
| a2_antes | 216.960, 180.576, 198.594, 161.104, 186.607 | 186.607 |
| a1_solo_indices | 74.657, 66.695, 64.069, 60.299, 57.604 | 64.069 |
| a1_despues | 98.570, 155.248, 87.827, 142.809, 88.621 | 98.570 |
| a2_solo_indices | 148.408, 148.426, 208.608, 151.846, 150.039 | 150.039 |
| a2_despues | 160.970, 134.289, 128.249, 145.723, 165.888 | 145.723 |

La diferencia inicial entre A2 con solo índices (150.039 ms) y con preagregación (145.723 ms) era pequeña respecto de la variación. Por eso se realizaron cinco pares adicionales alternando el orden: original con índices 157.710 ms y preagregada 128.066 ms de mediana. La segunda prueba volvió a favorecer la preagregación. Se conserva [confirmacion_a2.json](evidencias/20260922_151803/confirmacion_a2.json); sus tiempos no se mezclan con la tabla principal ni se presentan como garantía estadística universal.

## Identificación de cada join

Se enumeran los nodos del plan JSON de la muestra de mediana. La primera entrada de Nested Loop es la externa y la segunda la interna. En Hash Join, el segundo lado alimenta Hash/Parallel Hash; en Merge Join ambos lados llegan ordenados. Una entrada puede ser un conjunto ya unido, no una sola tabla.

### a1_antes

Costo raíz estimado: 8135.08..8213.86.

| Algoritmo | Primera entrada (externa/izquierda/sondeo) | Segunda entrada (interna/derecha/construcción) |
|---|---|---|
| Merge Join | pedido o, detalle_pedido d, producto p | categoria c |
| Nested Loop | pedido o, detalle_pedido d | producto p |
| Nested Loop | pedido o | detalle_pedido d |

### a1_solo_indices

Costo raíz estimado: 2989.12..3086.05.

| Algoritmo | Primera entrada (externa/izquierda/sondeo) | Segunda entrada (interna/derecha/construcción) |
|---|---|---|
| Merge Join | pedido o, detalle_pedido d, producto p | categoria c |
| Nested Loop | pedido o, detalle_pedido d | producto p |
| Nested Loop | pedido o | detalle_pedido d |

### a1_despues

Costo raíz estimado: 10073.63..11673.86.

| Algoritmo | Primera entrada (externa/izquierda/sondeo) | Segunda entrada (interna/derecha/construcción) |
|---|---|---|
| Hash Join | detalle_pedido d, pedido o, producto p | categoria c |
| Hash Join | detalle_pedido d, pedido o | producto p |
| Hash Join | detalle_pedido d | pedido o |

### a2_antes

Costo raíz estimado: 20236.16..20236.28.

| Algoritmo | Primera entrada (externa/izquierda/sondeo) | Segunda entrada (interna/derecha/construcción) |
|---|---|---|
| Hash Join | detalle_pedido d, pedido o | cliente u |
| Parallel Hash Join | detalle_pedido d | pedido o |

### a2_solo_indices

Costo raíz estimado: 16619.99..16620.12.

| Algoritmo | Primera entrada (externa/izquierda/sondeo) | Segunda entrada (interna/derecha/construcción) |
|---|---|---|
| Hash Join | detalle_pedido d, pedido o | cliente u |
| Parallel Hash Join | detalle_pedido d | pedido o |

### a2_despues

Costo raíz estimado: 16376.75..16376.88.

| Algoritmo | Primera entrada (externa/izquierda/sondeo) | Segunda entrada (interna/derecha/construcción) |
|---|---|---|
| Hash Join | detalle_pedido d, pedido o | cliente u |
| Parallel Hash Join | detalle_pedido d | pedido o |


## Planes completos y equivalencia

| Consulta / etapa | Plan legible | Cinco planes estructurados |
|---|---|---|
| A1 original | [TXT](evidencias/20260922_151803/a1_antes.txt) | [JSON](evidencias/20260922_151803/a1_antes.json) |
| A1 aceptada, índices | [TXT](evidencias/20260922_151803/a1_solo_indices.txt) | [JSON](evidencias/20260922_151803/a1_solo_indices.json) |
| A1 rango descartado | [TXT](evidencias/20260922_151803/a1_despues.txt) | [JSON](evidencias/20260922_151803/a1_despues.json) |
| A2 original | [TXT](evidencias/20260922_151803/a2_antes.txt) | [JSON](evidencias/20260922_151803/a2_antes.json) |
| A2 solo índices | [TXT](evidencias/20260922_151803/a2_solo_indices.txt) | [JSON](evidencias/20260922_151803/a2_solo_indices.json) |
| A2 aceptada, preagregación | [TXT](evidencias/20260922_151803/a2_despues.txt) | [JSON](evidencias/20260922_151803/a2_despues.json) |

Ambas parejas de reescrituras dieron EXCEPT ALL = 0 en las dos direcciones, y las listas ordenadas coincidieron (3 filas para A1 y 50 para A2). La equivalencia no obligó a aceptar A1: conservaba resultados, pero empeoraba el tiempo. La evidencia está en [sesion.json](evidencias/20260922_151803/sesion.json).

Propuestas escritas antes de aplicar: [propuestas_ia.md](propuestas_ia.md). Referencia técnica: [EXPLAIN](https://www.postgresql.org/docs/17/using-explain.html).
