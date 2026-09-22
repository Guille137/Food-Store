# Parte 4 — Competencia: ranking por gasto

Se desarrolla el ejemplo de ranking analítico indicado en la guía, continuando el criterio acordado para el TP3. La consulta común de esta entrega es A2: cliente–pedido–detalle, pedidos ENTREGADO de 2025 UTC, suma del precio histórico por cantidad, 50 clientes ordenados por gasto descendente e id ascendente. Contiene dos JOIN y agregación. Su [especificación](spec_analiticas.md) fija los parámetros para las tres estrategias.

Se reutilizan explícitamente las mediciones de A2 de la Parte 1 sobre la misma copia masiva; no se presenta una segunda ejecución inexistente ni datos de otros equipos.

| Equipo / entrega | Estrategia aplicada | Tiempo antes (ms) | Tiempo después (ms) | Mejora (x) |
|---|---|---:|---:|---:|
| Guille137 / Food-Store | Índice parcial de pedidos entregados y agregación por cliente antes de unir nombres | 186,607 | 145,723 | 1.28 |

## Estrategias y decisiones

| Intento | Mediana (ms) | Decisión y motivo |
|---|---:|---|
| Consulta original con índices del TP3 | 186,607 | Base de comparación |
| Mismo SQL con índices adicionales | 150,039 | Mejora, pero no es la variante final más rápida |
| Preagregación con índices | 145,723 | Elegida por menor mediana y mismos resultados |

Una confirmación de cinco pares alternando versiones volvió a favorecer la preagregación: 157,710 ms frente a 128,066 ms. Se informa separadamente porque los tiempos dependen del momento y carga; no se reemplazan silenciosamente las muestras originales.

Los dos joins siguen siendo de tipo Hash Join (uno paralelo). La mejora no se atribuye a un cambio de Hash Join a Nested Loop: el join con cliente recibe grupos ya agregados y transporta menos filas. El plan también lee pedidos entregados desde el índice parcial en lugar de recorrer toda la tabla.

Se eligió por Execution Time, no por cost. Las 50 filas completas y su orden coincidieron con la consulta inicial. No se declara un ganador entre equipos sin mediciones externas.

También se conserva el intento fallido del laboratorio A1: reescribir por rango llevó a tres Hash Join y 98,570 ms, por lo que se descartó aunque parecía favorable. La bitácora incluye propuestas que no funcionaron, no solo las aceptadas.

Evidencia: [antes](evidencias/20260922_151803/a2_antes.txt), [solo índices](evidencias/20260922_151803/a2_solo_indices.txt), [variante final](evidencias/20260922_151803/a2_despues.txt), [confirmación alternada](evidencias/20260922_151803/confirmacion_a2.json) y [registro de las cinco muestras de cada etapa](evidencias/20260922_151803/sesion.json). SQL: [original](a2_antes.sql), [elegido](a2_despues.sql), [índices](indices.sql).
