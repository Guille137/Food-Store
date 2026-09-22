# Parte 2 — Tabla de lectura crítica

Se contrasta la [respuesta literal del agente aislado](explicacion_ia.md) con el [plan real A1](evidencias/20260922_151803/a1_antes.txt). La revisión fue asistida por el agente principal y conserva las limitaciones de conocer solo el texto del plan en la explicación original.

| Afirmación de IA | ¿Correcta? | Corrección o evidencia |
|---|---|---|
| 1. Cost no son milisegundos; actual time sí. | Sí | El costo total raíz es 8213.86 y Execution Time es 84.142 ms; no son intercambiables. |
| 2. Tiempos/filas son promedios por loop; no se suman como tiempo de pared. | Sí | Hay paralelismo con un trabajador y dos loops en la rama; los nodos padre incluyen a los hijos. Los totales calculados de filas son aproximados por redondeo. |
| 3. El escaneo de pedido filtra estado y mes y subestima filas. | Sí | Filter explicita ENTREGADO y junio UTC; rows=148 frente a actual rows=2056 por loop. |
| 4–5. Nested Loop inferior: pedido externo y búsqueda de detalle interna. | Sí | La indentación ubica primero Parallel Seq Scan pedido y después Index Scan detalle con Index Cond que depende de o.id_pedido. El interno tiene 4112 loops. |
| 6. rows=1 y Rows Removed=0 no prueban una fila emitida y cero descartes en cada búsqueda. | Sí | Son promedios redondeados de 12336 loops. Esta precisión evita interpretar el cero como ausencia total de filtrado. |
| 7. Nested Loop superior: resultado pedido–detalle externo, producto interno. | Sí | El primer hijo es el Nested Loop inferior y el segundo busca producto por d.id_producto; son 12336 búsquedas. |
| 8. Sort por categoria_id prepara el lado izquierdo del merge. | Sí | Sort Key p.categoria_id, quicksort y valores de memoria diferenciados para líder/trabajador. |
| 9–10. Categoría se escanea y ordena en cada participante. | Sí | Seq Scan ordinario sobre c y Sort c.id_categoria muestran loops=2. No es un Parallel Seq Scan. |
| 11. Merge Join combina la rama pedido–detalle–producto con categoria. | Sí | Merge Cond p.categoria_id=c.id_categoria. Las cifras del plan solas no prueban restricciones de unicidad. |
| 12. El segundo ordenamiento prepara las claves de agregación. | Sí | Sort Key contiene mes convertido a date e id_categoria, distinto del ordenamiento previo. |
| 13–15. Se generan seis estados parciales y se obtienen tres grupos finales. | Sí | Partial GroupAggregate rows=3 loops=2, Gather Merge rows=6 y Finalize GroupAggregate rows=3. El plan no revela los nombres ni valores de las sumas. |
| 16. Shared hits no se multiplican por loops ni se suman entre ancestros. | Sí | La raíz ya contiene 56466 hits acumulados; el bloque Planning contiene 40 aparte. |
| 17. Planificación 0.745 ms y ejecución 84.142 ms; no se puede asegurar una optimización solo con ese plan. | Sí | Son los tiempos reportados. La Parte 1 demuestra que una reescritura aparentemente razonable puede empeorar. |

No se detectaron afirmaciones falsas en la explicación recibida. Se preservan las precisiones reales sobre promedios, redondeo, lados de los Nested Loop y costo frente a tiempo; no se inventó un error para completar la tabla. La subestimación observada no basta para atribuir su causa a estadísticas desactualizadas: se había ejecutado ANALYZE y el agente no recibió ese contexto.

Referencia: [EXPLAIN de PostgreSQL](https://www.postgresql.org/docs/17/using-explain.html).
