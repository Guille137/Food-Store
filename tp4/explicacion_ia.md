# Parte 2 — Explicación de IA con contexto aislado

Se mantuvo la autorización del alumno para usar un segundo agente que reciba solo el plan. Se inició una conversación sin historial y se le indicó que no utilizara herramientas ni archivos.

## Prompt

Explicá este plan PostgreSQL EXPLAIN ANALYZE en español, nodo por nodo, con afirmaciones numeradas. Identificá las entradas externa/interna en cada Nested Loop y las entradas de los demás joins. Distinguí cost de tiempo real, y promedios por loop de totales. Recibís únicamente este texto: no uses herramientas ni archivos ni supongas SQL, índices u otros planes no mostrados. Indicá los límites de lo que puede inferirse.

Se adjuntó el texto completo de [a1_antes.txt](evidencias/20260922_151803/a1_antes.txt), sin la consulta, el esquema ni otros planes. Se seleccionó este plan real porque contiene dos Nested Loop y un Merge Join.

## Respuesta literal

1. **Cómo leer las cifras.** `cost=a..b` representa el costo estimado de inicio y el costo total, en unidades del optimizador; **no son milisegundos**. `rows` es la cantidad estimada de filas emitidas y `width`, su ancho medio estimado en bytes. En `actual time=a..b`, los tiempos sí están expresados en milisegundos: hasta emitir la primera fila y hasta finalizar el nodo, respectivamente.

2. **Qué significa `loops`.** Los tiempos reales y las filas mostrados son promedios por ejecución del nodo. Por ejemplo, `rows=5757 loops=2` representa aproximadamente 11.514 filas entre ambas ejecuciones; las filas se muestran redondeadas. En esta rama paralela, dos ejecuciones corresponden a la participación del líder y del trabajador. Multiplicar tiempos por `loops` no da el tiempo de pared de la consulta: las ejecuciones pueden superponerse y los tiempos de los padres incluyen trabajo de sus hijos.

3. **`Parallel Seq Scan on pedido o`: lectura y filtro de pedidos.** Recorre la tabla en paralelo y conserva filas con `estado = 'ENTREGADO'` y cuyo mes, calculado con la expresión de zona horaria mostrada, coincide con junio de 2025. Emite en promedio 2.056 filas por ejecución, aproximadamente **4.112 en total**, frente a 148 estimadas. Descarta por el filtro un promedio de 97.946 filas por ejecución, aproximadamente 195.892 entre ambas. Su tiempo es `4.947..15.994 ms`, promedio por ejecución. El plan muestra un recorrido secuencial; no permite afirmar por qué se eligió ni qué otros índices existen.

4. **`Index Scan using pk_detalle_pedido on detalle_pedido d`: búsqueda de detalles.** Usa el índice indicado para buscar `id_pedido = o.id_pedido`. Se ejecuta **4.112 veces**, una por cada pedido recibido como entrada externa del join siguiente. Devuelve un promedio de tres filas por búsqueda, con tiempos medios de `0.004..0.005 ms`. El nombre del índice no permite deducir su definición completa.

5. **`Nested Loop` inferior: pedidos con detalles.** Su **entrada externa** es `Parallel Seq Scan on pedido o`; su **entrada interna** es el `Index Scan` sobre `detalle_pedido d`. Por cada pedido externo ejecuta la búsqueda interna de detalles. Emite un promedio de 6.168 filas en dos ejecuciones, aproximadamente **12.336 filas totales**, frente a 445 estimadas. El tiempo `4.990..28.212 ms` incluye el trabajo de sus entradas.

6. **`Index Scan using pk_producto on producto p`: búsqueda de productos.** Busca `id_producto = d.id_producto` y aplica luego `Filter: activo`. Se ejecuta **12.336 veces**, una por cada fila externa del join superior. `rows=1` es un promedio redondeado: no demuestra que todas las búsquedas emitan exactamente una fila. Igualmente, `Rows Removed by Filter: 0` **no demuestra que no se haya descartado ningún producto**, porque también es un promedio redondeado por ejecución. El tiempo medio mostrado es `0.003..0.003 ms`; la igualdad responde a la precisión de presentación y no implica trabajo instantáneo.

7. **`Nested Loop` superior: incorporación de productos activos.** Su **entrada externa** es el resultado del `Nested Loop` inferior, que combina pedidos y detalles. Su **entrada interna** es el `Index Scan` sobre `producto p`. Produce un promedio de 5.757 filas en dos ejecuciones, aproximadamente **11.514 en total**, frente a 401 estimadas. Hay menos filas de salida que filas externas; sin las restricciones del esquema y cifras sin redondear no puede atribuirse toda la diferencia exclusivamente al filtro `activo`, ni reconstruirse exactamente cuántas búsquedas no encontraron producto.

8. **`Sort` por `p.categoria_id`: preparación de la entrada izquierda del merge.** Ordena el resultado del `Nested Loop` superior por la clave de categoría. Recibe y emite unas 5.757 filas por ejecución. Usa `quicksort`, con 502 kB informados para el líder y 237 kB para `Worker 0`; no se muestra un ordenamiento en disco. Su tiempo `50.471..50.873 ms` incluye obtener las filas del hijo y ordenarlas, no solamente compararlas.

9. **`Seq Scan on categoria c`: lectura de categorías.** Recorre `categoria` y aplica `Filter: activo`. Emite tres filas por ejecución y se ejecuta dos veces, una en cada participante de esta rama paralela. A diferencia del recorrido paralelo de pedidos, este es un `Seq Scan` ordinario ejecutado por ambos participantes. Sus tiempos medios son `0.458..0.459 ms`.

10. **`Sort` por `c.id_categoria`: preparación de la entrada derecha del merge.** Ordena las categorías activas por `c.id_categoria`. Emite tres filas por ejecución y usa `quicksort`, con 25 kB en cada participante. Sus tiempos medios son `0.473..0.474 ms`.

11. **`Merge Join`: combinación con categorías.** Su **entrada izquierda** es el `Sort` de pedidos, detalles y productos por `p.categoria_id`; su **entrada derecha** es el `Sort` de categorías activas por `c.id_categoria`. Combina ambas secuencias ordenadas mediante `p.categoria_id = c.id_categoria`. Emite unas 5.757 filas por ejecución, frente a 401 estimadas, con tiempos medios de `50.951..54.049 ms`. Que su cantidad de salida coincida con la izquierda en las cifras mostradas no demuestra por sí solo una relación uno a uno: faltan restricciones y cifras exactas.

12. **`Sort` por las claves de agrupación.** Ordena la salida del `Merge Join` por el mes convertido a `date` y por `c.id_categoria`. Este ordenamiento es distinto del anterior por categoría: prepara los datos para agruparlos. Emite unas 5.757 filas por ejecución, con tiempos medios de `55.443..55.884 ms`. Usa `quicksort`, con 584 kB para el líder y 275 kB para el trabajador.

13. **`Partial GroupAggregate`: agregación parcial.** Cada participante procesa su entrada ordenada y calcula estados parciales de agregación para las claves indicadas. Produce tres filas parciales en promedio por ejecución, seis entre ambas, con tiempos medios de `56.690..58.598 ms`. Se estimaban 401 filas por ejecución. El texto no muestra las funciones agregadas, por lo que no puede afirmarse si calcula sumas, conteos u otras operaciones.

14. **`Gather Merge`: reunión de resultados paralelos.** Recibe las salidas ordenadas de la agregación parcial del líder y del trabajador y las combina conservando el orden. Se planificó un trabajador y se lanzó uno. Emite **seis filas**, con `loops=1` y tiempos de `78.895..83.813 ms`. Esas seis filas son resultados parciales, no necesariamente seis grupos distintos.

15. **`Finalize GroupAggregate`: resultado final.** Combina los estados parciales que corresponden a las mismas claves y completa las agregaciones. Produce **tres filas finales**, frente a 681 estimadas, con tiempos de `80.417..83.839 ms` y una ejecución. El filtro fija la expresión mensual a junio de 2025; por tanto, las filas que llegan a agruparse comparten ese mes. Las tres filas finales representan tres combinaciones de mes y categoría, aunque el plan no muestra sus valores ni sus resultados agregados.

16. **Buffers.** `shared hit` cuenta accesos a bloques encontrados en los buffers compartidos de PostgreSQL; no son cantidades de bloques distintos. Los valores de los nodos padres incluyen los de sus descendientes, por lo que **no deben sumarse todos los nodos**. Tampoco deben multiplicarse por `loops`: estos contadores ya acumulan las ejecuciones informadas. La raíz muestra 56.466 accesos de este tipo durante la ejecución; la planificación informa otros 40. No aparecen lecturas `shared read` ni actividad temporal en este texto.

17. **Tiempo global y límites del diagnóstico.** La planificación demoró **0,745 ms** y la ejecución completa **84,142 ms**. La diferencia entre el tiempo final del nodo raíz y `Execution Time` corresponde a trabajo de ejecución que esa medición del nodo no abarca. Se observa una subestimación considerable de filas desde el filtro de pedidos y una sobreestimación de grupos finales. El plan, por sí solo, no identifica su causa ni permite recomendar con certeza un índice o una reescritura: faltan el SQL completo, las estadísticas, el esquema y alternativas medidas.
