# Parte 2 — Optimización medida

## Entorno y método

PostgreSQL 17.11 en Windows, instancia local aislada, puerto 55432 y zona de sesión UTC. Base: `food_store_tp3_20260922_142245_trabajo`. Carga: 50.003 productos, 20.001 clientes, 200.003 pedidos y 600.000 detalles, incluyendo el seed del TP2.

Se eligieron tres variantes propias sobre el modelo, permitidas por la consigna. El archivo `queries.sql` de la cátedra no estaba disponible. No se borraron los índices originales ni se forzó el optimizador. Se ejecutó VACUUM (ANALYZE) antes de cada fase, un calentamiento por consulta y cinco mediciones EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON). La tabla compara las medianas de Execution Time y los costos del plan de la muestra correspondiente; cost está en unidades del optimizador, no en milisegundos.

Los planes TXT son una sexta ejecución de diagnóstico y por eso sus tiempos pueden diferir de la mediana de los cinco JSON. Las lecturas estaban mayormente en caché: esta prueba mide un escenario local con caché caliente, no garantiza los mismos factores en producción. Q1 ya tardaba pocos milisegundos; se documenta como reducción medible, sin exagerar su impacto perceptible.

## Comparación

| Consulta | Plan antes: nodos, costo, tiempo | Cambio aplicado | Plan después: nodos, costo, tiempo | Mejora antes/después |
|---|---|---|---|---|
| Q1 | Limit → Sort → Bitmap Heap Scan → Bitmap Index Scan; cost 1000.56..1000.69; **4.715 ms** | Índice parcial por categoría, precio e id; INCLUDE(nombre). | Limit → Index Only Scan; cost 0.41..2.99; **0.060 ms** | **78.58×** |
| Q2 | Gather Merge → Sort → Seq Scan; cost 6027.91..6095.53; **41.193 ms** | Rango UTC semiabierto y un índice por fecha e id. | Index Only Scan; cost 0.42..23.94; **0.104 ms** | **396.09×** |
| Q3 | Aggregate → Gather → Aggregate → Seq Scan; cost 1000.0..7947.31; **51.755 ms** | Índice por producto que incluye cantidad y precio histórico. | Aggregate → Index Only Scan; cost 0.42..4.8; **0.038 ms** | **1361.97×** |

Las tres propuestas mejoraron la mediana. Se aceptan para estas consultas y distribución de datos; no se deduce que mejoren todas las cargas posibles.

## Planes completos y propuestas

| Consulta | SQL original | Plan antes | Plan después | Todas las mediciones |
|---|---|---|---|---|
| Q1: listado de productos | [consultas_lentas.sql](consultas_lentas.sql) | [Texto](evidencias/20260922_142245/q1_antes.txt) | [Texto](evidencias/20260922_142245/q1_despues.txt) | [Antes](evidencias/20260922_142245/q1_antes.json), [después](evidencias/20260922_142245/q1_despues.json) |
| Q2: pedidos del día UTC | [consultas_lentas.sql](consultas_lentas.sql) | [Texto](evidencias/20260922_142245/q2_antes.txt) | [Texto](evidencias/20260922_142245/q2_despues.txt) | [Antes](evidencias/20260922_142245/q2_antes.json), [después](evidencias/20260922_142245/q2_despues.json) |
| Q3: resumen histórico de producto | [consultas_lentas.sql](consultas_lentas.sql) | [Texto](evidencias/20260922_142245/q3_antes.txt) | [Texto](evidencias/20260922_142245/q3_despues.txt) | [Antes](evidencias/20260922_142245/q3_antes.json), [después](evidencias/20260922_142245/q3_despues.json) |

Las [propuestas de IA](propuestas_ia.md) se redactaron después de leer los planes iniciales y antes de aplicar [indices.sql](indices.sql). El SQL final está en [consultas_optimizadas.sql](consultas_optimizadas.sql). Cada creación de índice se ensayó primero con ROLLBACK y luego se confirmó, con respaldo previo de la copia.

## Qué cambió en los planes

- Q1 dejó de reunir miles de filas y ordenarlas: el Index Only Scan accedió por categoría y rango de precio, y LIMIT cortó a las 50 filas. El TXT registra 5 buffers frente a 475 en el diagnóstico anterior.
- Q2 pasó del escaneo paralelo con conversión por fila a un rango sobre fecha. El rango preserva el día UTC, con extremo superior exclusivo; el índice también proporciona el orden. El TXT registra 7 buffers frente a 2.986 en el plan anterior.
- Q3 localizó las 12 líneas del producto con Index Only Scan en lugar de filtrar toda detalle_pedido en paralelo. El TXT registra 4 buffers frente a 3.822.

Los tres diagnósticos finales muestran Heap Fetches=0, bajo las condiciones de visibilidad de esta copia recién mantenida. Eso no garantiza que siempre sea cero después de futuras escrituras.

## Equivalencia y decisiones descartadas

Se comparó cada consulta original con su versión optimizada mediante EXCEPT ALL en ambas direcciones: las tres devolvieron (0,0). También coincidieron las listas completas ordenadas. No se usó solo el tiempo como criterio de aceptación.

No se probaron índices duplicados de categoría ni un índice aislado sobre activo, y no se deshabilitó Seq Scan: los motivos están en propuestas_ia.md. Se registran como alternativas descartadas por análisis, no como ensayos de rendimiento. No hubo entre los tres candidatos aplicados una regresión de mediana que ocultar.

Costos de almacenamiento observados: aproximadamente 2,55 MiB para el índice de productos, 7,75 MiB para pedidos y 18,06 MiB para detalles. Estos índices agregan mantenimiento a futuras escrituras; la prueba no mide ese costo de INSERT/UPDATE.

## Incidencia del ejecutor

Después de cargar y confirmar los datos, el primer intento de medición se interrumpió porque el separador de consultas interpretó un punto y coma de un comentario como fin de sentencia. Se corrigió el lector para excluir comentarios y se reanudaron las tres mediciones sobre la misma copia, sin volver a cargar los datos. Se verificaron los conteos y el ensayo revertido antes de reanudar. Los planes publicados corresponden a la ejecución completa posterior a esa corrección.

Fuentes: [EXPLAIN](https://www.postgresql.org/docs/17/using-explain.html), [índices multicolumna](https://www.postgresql.org/docs/17/indexes-multicolumn.html). Registro estructurado: [sesion.json](evidencias/20260922_142245/sesion.json).
