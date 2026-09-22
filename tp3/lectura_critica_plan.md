# Parte 3 — Contraste de la explicación con el plan

Se utilizó el [plan real de Q1 con índice](evidencias/20260922_142245/q1_despues.txt). La [respuesta literal y el prompt](explicacion_ia_plan.md) pertenecen a un agente aislado, sin el SQL ni los planes previos. La revisión siguiente fue realizada con asistencia del agente principal; no se atribuye al alumno una revisión personal que aún deba realizar para su defensa.

| Afirmación de la IA | ¿Correcta? | Evidencia o precisión |
|---|---|---|
| 1. Index Only Scan obtiene filas y Limit limita a 50. | Sí, con precisión de lectura. | Son los dos nodos del plan y el superior devuelve 50. “De abajo hacia arriba” describe el flujo de filas; no significa que se materialice todo el escaneo antes del Limit: este puede detener a su hijo. |
| 2. Categoría 1, precio entre 1000 y 1500 incluidos, tipo numeric. | Sí. | Index Cond contiene igualdad, >=, <= y conversiones ::numeric explícitas. |
| 3. Datos obtenibles desde el índice y cero visitas al heap. | Sí, para esta ejecución. | El nodo es Index Only Scan y Heap Fetches=0. No equivale a una garantía después de futuras escrituras. |
| 4. Costos 0.41..85.65 estimados, 1655 filas estimadas y ancho 28 bytes. | Sí. | Distingue estimación de medición y aclara que cost no son milisegundos. |
| 5. El índice entregó 50 filas en un loop; no se conoce el total real de coincidencias. | Sí. | actual rows=50, loops=1 y Limit detienen el recorrido. Sería incorrecto calcular un error de cardinalidad como 1655/50 sin tener en cuenta ese corte. |
| 6. Limit tiene costo parcial y tiempos que incluyen al hijo. | Sí. | El costo total del Limit es 2.99 frente a 85.65 del recorrido completo estimado. Los tiempos del padre y del hijo no se suman. |
| 7. shared hit=5 son accesos en buffers; no se duplican por aparecer en padre e hijo. | Sí. | Ambas líneas informan hit=5; no hay shared read. Tampoco se puede convertir esos accesos en cinco bloques únicos garantizados. |
| 8. Planificación 0.115 ms y ejecución 0.050 ms, sin equivalencia con latencia de aplicación. | Sí. | Son los valores del cierre del plan; no contienen el viaje de red ni la presentación de resultados en una aplicación. |
| 9. No se puede reconstruir todo el SQL, el índice ni comparar con otro plan. | Sí. | El texto recibido no incluye columnas SELECT, DDL ni una medición previa. El agente no inventa esos datos ni una mejora relativa. |

No se detectaron afirmaciones falsas en la respuesta obtenida. Se registró la precisión necesaria en la frase “de abajo hacia arriba”; no se introdujo deliberadamente un error para llenar la tabla. Esta revisión comprueba el contenido contra los valores del plan y delimita qué inferencias no serían válidas.

Referencia conceptual: [documentación de EXPLAIN de PostgreSQL](https://www.postgresql.org/docs/17/using-explain.html).
