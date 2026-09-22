# Guía de comprensión y defensa

La defensa oral es personal. Esta guía sirve para estudiar decisiones ya medidas; no afirma que el alumno haya realizado la defensa ni revisado personalmente cada línea.

1. **¿Por qué cargar tantos datos?** Los planes y beneficios de índices dependen del volumen y la selectividad. Con pocas filas, un escaneo completo puede resultar más barato.
2. **¿Qué garantiza la carga?** Usa las FKs reales devueltas por INSERT, cantidades válidas y transiciones del TP2. Las filas se generan de manera determinista y se ensayan en otra copia con ROLLBACK.
3. **¿Para qué ANALYZE?** Actualiza estimaciones estadísticas que usa el optimizador; no es por sí mismo una creación de índices.
4. **¿Cost es tiempo?** No: cost usa unidades del planificador; Execution Time informa milisegundos reales del ensayo. La tabla compara medianas de cinco ejecuciones.
5. **¿Por qué el índice de Q1 tiene ese orden?** Primero la igualdad de categoría, luego el rango y orden de precio y finalmente id como desempate. Es parcial porque esta consulta requiere activo=TRUE.
6. **¿Por qué INCLUDE(nombre)?** Permite obtener esa columna desde el índice sin usarla como clave de orden o búsqueda. Index Only Scan puede evitar visitas al heap cuando la visibilidad lo permite.
7. **¿Por qué reescribir la fecha?** El intervalo UTC incluye desde el inicio del día hasta antes del siguiente y permite buscar por la columna sin transformarla fila por fila.
8. **¿Por qué la PK de detalles no bastaba?** Empieza por id_pedido; el filtro usa solo id_producto. El nuevo índice permite localizar directamente esas líneas.
9. **¿Se pueden sumar los tiempos de nodos?** No directamente: los superiores incluyen trabajo de sus descendientes, y los nodos con loops muestran promedios por ejecución. En paralelo tampoco se obtiene el tiempo de pared sumando trabajadores.
10. **¿Por qué dos direcciones de EXCEPT ALL?** Una dirección sola no detecta filas sobrantes del otro lado. ALL conserva diferencias de duplicados; además se verifica el orden aparte.
11. **¿Qué sacrifican los índices?** Espacio y mantenimiento en escrituras. La mejora local con caché caliente no es una promesa de velocidad universal.
12. **¿Qué se probó en la competencia?** El ejemplo de la guía: productos por categoría, precio y orden. En una copia sin el índice aplicable se midió la base y se compararon índices simple y compuesto parcial. Se eligió la menor mediana con las mismas 50 filas ordenadas; el registro no atribuye resultados a otros equipos.
