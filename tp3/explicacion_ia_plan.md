# Parte 3 — Explicación recibida de un agente aislado

El alumno autorizó usar un segundo agente con solo el plan. Se abrió una sesión sin historial de la conversación y sin acceso a herramientas para esta tarea.

## Prompt exacto

Explicá en español el siguiente plan EXPLAIN ANALYZE, nodo por nodo. Recibís únicamente este texto; no uses herramientas ni consultes archivos u otras fuentes. Numerá tus afirmaciones para facilitar su revisión. Indicá los límites de lo que se puede inferir y no supongas consultas o planes previos.

```text
Limit  (cost=0.41..2.99 rows=50 width=28) (actual time=0.015..0.036 rows=50 loops=1)
  Buffers: shared hit=5
  ->  Index Only Scan using tp3_producto_categoria_precio on producto  (cost=0.41..85.65 rows=1655 width=28) (actual time=0.014..0.031 rows=50 loops=1)
        Index Cond: ((categoria_id = 1) AND (precio_lista >= '1000'::numeric) AND (precio_lista <= '1500'::numeric))
        Heap Fetches: 0
        Buffers: shared hit=5
Planning Time: 0.115 ms
Execution Time: 0.050 ms
```

## Respuesta literal

1. **El plan se lee de abajo hacia arriba:** un `Index Only Scan` obtiene filas de `producto` usando el índice `tp3_producto_categoria_precio`, y el nodo `Limit` restringe la salida a 50 filas.

2. **`Index Cond`** muestra las condiciones aplicadas mediante el índice: `categoria_id = 1` y `precio_lista` entre 1000 y 1500, con ambos extremos incluidos. `::numeric` indica el tipo de los valores usados en la comparación.

3. **`Index Only Scan`** significa que los datos necesarios pueden obtenerse del índice. PostgreSQL puede necesitar consultar la tabla para comprobar visibilidad; aquí, **`Heap Fetches: 0`** confirma que esta ejecución no necesitó esas consultas.

4. **Estimaciones del recorrido del índice:** `cost=0.41..85.65` representa el costo inicial y el costo total estimado si se completara ese nodo. Son unidades del planificador, no milisegundos. `rows=1655` estima cuántas filas produciría el recorrido completo bajo esas condiciones; `width=28` estima el tamaño promedio de cada fila de salida, en bytes.

5. **Medición del recorrido del índice:** `actual time=0.014..0.031 rows=50 loops=1` indica que produjo su primera fila aproximadamente a los 0,014 ms y terminó a los 0,031 ms, entregando 50 filas en una ejecución. El `Limit` dejó de solicitar filas al alcanzar 50: este resultado no demuestra que solo existan 50 coincidencias ni permite contrastar las 1655 estimadas con el total real.

6. **Nodo `Limit`:** `rows=50` es su cantidad estimada de filas de salida, y `actual rows=50` confirma la cantidad entregada. `cost=0.41..2.99` refleja que se espera obtener esas filas sin completar el recorrido del índice. `actual time=0.015..0.036` registra el tiempo hasta la primera fila y hasta completar el nodo. Los tiempos de los nodos superiores incluyen el trabajo de sus hijos; no deben sumarse.

7. **`Buffers: shared hit=5`** indica cinco accesos a bloques encontrados en los buffers compartidos de PostgreSQL. No equivale necesariamente a cinco bloques distintos. Los cinco accesos informados en `Limit` incluyen los de su hijo: no son diez en total. El plan no informa lecturas de bloques hacia esos buffers durante la ejecución.

8. **Tiempos generales:** `Planning Time: 0.115 ms` corresponde a la planificación, y `Execution Time: 0.050 ms`, a la ejecución medida por PostgreSQL. Este último incluye trabajo adicional al reflejado en el tiempo del nodo superior. No representa necesariamente la latencia completa percibida por una aplicación.

9. **Límites de la interpretación:** el texto no permite reconstruir la consulta completa, identificar todas sus columnas de salida, conocer la definición exacta del índice ni afirmar que el resultado tenga un orden garantizado. Tampoco permite comparar con planes anteriores o asegurar que este rendimiento se mantendrá con otros datos, caché o carga.
