# TP5 — Índices, vistas y vista materializada

Ejecución real del 22/09/2026 en PostgreSQL 17.11, Windows, instancia local aislada. [Sesión completa](evidencias/20260922_194616/sesion.json). No se modificaron columnas, restricciones ni funciones/triggers de las tablas heredadas; se comprobaron sus definiciones antes y después.

## Base y método

Origen: `food_store_tp4_20260922_151803`, con todos los índices de TP3 y TP4. Se crearon dos copias nuevas: `food_store_tp5_20260922_194616_antes` y `food_store_tp5_20260922_194616`. No se modificó el origen ni se eliminó ningún índice heredado. Volumen: 50.003 productos, 20.001 clientes, 200.003 pedidos y 600.000 detalles. Para medir escritura se agregó un pedido PENDIENTE vacío en ambas copias: las pruebas parten de 200.004 pedidos. Las 800 líneas de cada ensayo siempre se revierten.

La carga proviene de `tp3/carga_masiva.sql`. El nombre `data.sql` de la guía corresponde aquí a `datos_iniciales.sql` más esa ampliación. El modelo usa `cliente` donde la guía ejemplifica `usuario`; no tiene contraseña, eliminado ni total de pedido. Se preserva el modelo, según la prohibición de alterar tablas de la página 2.

Las consultas exactas están en [queries.sql](queries.sql). Son ampliaciones de los usos de catálogo, cola de pedidos y desglose de ventas del proyecto. Las consultas de TP3/TP4 ya optimizadas se conservan: no se degradan para fabricar nuevos casos. Las frecuencias de [specs/indices.md](specs/indices.md) son supuestos de uso, no mediciones de tráfico.

Lectura: un calentamiento, cinco `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` y mediana de **Execution Time**, sin sumar Planning Time. Los `.txt` son una ejecución adicional para facilitar lectura; su tiempo puede diferir de la mediana. Se midió inmediatamente antes y después de cada índice, con los mismos datos y la misma consulta. Se comprobaron valores y orden antes de aceptar. No se deshabilitó Seq Scan ni se forzó un plan.

Configuración: shared_buffers 128 MiB, work_mem 4 MiB, random_page_cost 4, seq_page_cost 1, hasta dos trabajadores paralelos y JIT habilitado. VACUUM ANALYZE inicial; caché caliente. El equipo y la concurrencia pueden cambiar los tiempos, particularmente el arranque de trabajadores de Q3. Las cifras no son garantías de producción.

Cada DDL tuvo respaldo previo, ensayo con BEGIN/ROLLBACK, comprobación y posterior COMMIT en la copia. Los dumps se conservan fuera de Git. Las especificaciones se versionaron antes del SQL; cada índice, cada vista y la materializada tienen su propio commit.

## A. Índices aceptados

| Consulta | Filas devueltas | Antes, mediana ms | Después, mediana ms | Factor antes/después | Cambio observado |
|---|---:|---:|---:|---:|---|
| Q1: nombre sin distinguir mayúsculas | 1 | 9,870 | 0,024 | 411,25 | Seq Scan → Bitmap Heap/Index Scan |
| Q2: confirmados con tarjeta | 16.667 | 19,342 | 2,776 | 6,97 | Seq Scan + Sort → Index Only Scan |
| Q3: precio histórico ≥ 4990 | 1.464 | 58,102 | 0,311 | 186,82 | Parallel Seq Scan + Sort/Gather Merge → Index Only Scan |

I1: `tp5_producto_nombre_activo`, B-tree sobre `lower(nombre)` con `WHERE activo`. El UNIQUE previo de nombre no ordena la expresión. El nuevo índice reduce bloques compartidos del plan de muestra de 459 a 4. La estimación inicial todavía es 225 frente a una fila real: el acceso mejora sin afirmar que la estimación sea exacta. No se extiende esta conclusión a búsquedas por fragmento ni a eliminación de acentos.

I2: `tp5_pedido_confirmado_tarjeta`, parcial por ambos literales, claves `(fecha,id_pedido)` e INCLUDE de estado, forma de pago y cliente. El subconjunto es aproximadamente el 8,33% de los pedidos. Sirve para filtrar y ordenar la cola; el índice de entregados del TP4 no cubre confirmados. El índice general por fecha conserva otros usos. El plan de muestra baja de 2.942 a 85 bloques y evita ordenar. Un pedido que cambia de estado puede entrar/salir del índice. No se asegura su uso con planes genéricos cuyos parámetros impidan demostrar el predicado.

I3: `tp5_detalle_precio`, B-tree completo `(precio_unitario,id_pedido,id_producto) INCLUDE(cantidad)`. Permite rangos de otros umbrales y entrega el orden solicitado. La PK empieza por pedido, y los índices previos por pedido o producto no dan este acceso por precio. El filtro selecciona el 0,244% de 600.000 líneas. Se pasa de 3.908 a 11 bloques en los planes de muestra. INCLUDE y el mapa de visibilidad permiten Index Only Scan con cero Heap Fetches en esta lectura; después de escrituras puede necesitar consultar el heap.

Tamaño al terminar, mediante `pg_relation_size` (incluye efectos físicos de pruebas revertidas): I1 1.851.392 bytes; I2 696.320; I3 24.354.816. I3 es el costo principal de espacio y de nuevas altas; se acepta para el uso especificado de auditoría, no como recomendación universal para cualquier carga.

### Planes completos antes y después

Los cinco planes JSON de cada medición y los textos originales están en [evidencias/20260922_194616](evidencias/20260922_194616). A continuación se incluyen los textos, sin recortar nodos.

#### i1_antes

```text
Seq Scan on producto  (cost=0.00..1209.05 rows=225 width=36) (actual time=2.356..9.880 rows=1 loops=1)
  Filter: (activo AND (lower((nombre)::text) = 'tp3 producto 12345'::text))
  Rows Removed by Filter: 50002
  Buffers: shared hit=459
Planning Time: 0.129 ms
Execution Time: 9.898 ms
```

#### i1_despues

```text
Bitmap Heap Scan on producto  (cost=10.16..396.55 rows=225 width=36) (actual time=0.014..0.015 rows=1 loops=1)
  Recheck Cond: ((lower((nombre)::text) = 'tp3 producto 12345'::text) AND activo)
  Heap Blocks: exact=1
  Buffers: shared hit=4
  ->  Bitmap Index Scan on tp5_producto_nombre_activo  (cost=0.00..10.10 rows=225 width=0) (actual time=0.008..0.008 rows=1 loops=1)
        Index Cond: (lower((nombre)::text) = 'tp3 producto 12345'::text)
        Buffers: shared hit=3
Planning Time: 0.065 ms
Execution Time: 0.024 ms
```

#### i2_antes

```text
Sort  (cost=7121.80..7163.82 rows=16809 width=24) (actual time=17.373..18.623 rows=16667 loops=1)
  Sort Key: fecha, id_pedido
  Sort Method: quicksort  Memory: 1550kB
  Buffers: shared hit=2942
  ->  Seq Scan on pedido  (cost=0.00..5942.06 rows=16809 width=24) (actual time=3.897..14.381 rows=16667 loops=1)
        Filter: ((estado = 'CONFIRMADO'::estado_pedido) AND (forma_pago = 'TARJETA'::forma_pago))
        Rows Removed by Filter: 183337
        Buffers: shared hit=2942
Planning Time: 0.118 ms
Execution Time: 19.284 ms
```

#### i2_despues

```text
Index Only Scan using tp5_pedido_confirmado_tarjeta on pedido  (cost=0.29..599.71 rows=16809 width=24) (actual time=0.011..2.325 rows=16667 loops=1)
  Heap Fetches: 0
  Buffers: shared hit=85
Planning Time: 0.118 ms
Execution Time: 2.770 ms
```

#### i3_antes

```text
Gather Merge  (cost=7973.86..8110.13 rows=1168 width=17) (actual time=51.361..56.349 rows=1464 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  Buffers: shared hit=3908
  ->  Sort  (cost=6973.83..6975.29 rows=584 width=17) (actual time=24.222..24.242 rows=488 loops=3)
        Sort Key: precio_unitario, id_pedido, id_producto
        Sort Method: quicksort  Memory: 90kB
        Buffers: shared hit=3908
        Worker 0:  Sort Method: quicksort  Memory: 30kB
        Worker 1:  Sort Method: quicksort  Memory: 34kB
        ->  Parallel Seq Scan on detalle_pedido  (cost=0.00..6947.00 rows=584 width=17) (actual time=0.041..23.743 rows=488 loops=3)
              Filter: (precio_unitario >= '4990'::numeric)
              Rows Removed by Filter: 199512
              Buffers: shared hit=3822
Planning Time: 0.101 ms
Execution Time: 56.424 ms
```

#### i3_despues

```text
Index Only Scan using tp5_detalle_precio on detalle_pedido  (cost=0.42..56.94 rows=1401 width=17) (actual time=0.010..0.294 rows=1464 loops=1)
  Index Cond: (precio_unitario >= '4990'::numeric)
  Heap Fetches: 0
  Buffers: shared hit=11
Planning:
  Buffers: shared hit=4
Planning Time: 0.149 ms
Execution Time: 0.356 ms
```

### Costo de escritura

Se usaron dos copias con los mismos datos y el mismo pedido vacío, con/sin los tres índices nuevos. Un calentamiento y siete pares, alternando qué copia se mide primero. En cada transacción se insertaron los mismos 800 productos activos, stock suficiente, cantidad 1 y precio de lista, comprobando 800 filas antes de ROLLBACK y cero después. Los triggers permanecieron habilitados.

| Prueba | Antes: mediana [mín.–máx.] ms | Después: mediana [mín.–máx.] ms | Incremento de mediana |
|---|---:|---:|---:|
| 800 INSERT individuales | 180,269 [178,631–200,521] | 188,844 [186,834–198,410] | 4,76% |
| Un INSERT SELECT de 800 filas | 47,392 [46,986–52,739] | 50,960 [50,239–56,302] | 7,53% |

La primera prueba mide tiempo del cliente desde el primer INSERT hasta que finaliza el último, incluyendo viajes locales y triggers; excluye preparación, comprobaciones, COMMIT y ROLLBACK. La segunda mide Execution Time del servidor con EXPLAIN ANALYZE, incluyendo triggers y su instrumentación. Son dos métodos distintos: no comparar sus tiempos entre sí para atribuir toda la diferencia a los índices.

En el INSERT por lote, la mediana de WAL Records pasó de 4.011 a 4.811 y la de WAL Bytes de 279.857 a 343.857 (+800 registros y +64.000 bytes). Son contadores de la sentencia observada, no una predicción fija para toda carga. [Todas las muestras y planes](evidencias/20260922_194616/escritura.json).

El mantenimiento directo nuevo sobre detalle corresponde a I3; I1/I2 están en otras tablas y no reciben entradas nuevas por estos INSERT, aunque los triggers consultan producto/pedido. Los tiempos fluctúan y sus rangos se superponen; el resultado sugiere un costo moderado y el WAL aporta evidencia adicional. La prueba no representa inserciones concurrentes, latencia de COMMIT ni una aplicación de producción. Los ROLLBACK no deshacen WAL, caché ni todos los efectos físicos de las páginas.

### Propuesta descartada por sobreindexación

La propuesta evaluada fue `CREATE INDEX tp5_detalle_pedido_redundante ON detalle_pedido(id_pedido)`. **No se ejecutó y no está en indices.sql**. La PK `(id_pedido,id_producto)` ya permite buscar por su prefijo y `tp4_detalle_pedido_cubierto` empieza por la misma clave e incluye todos los campos del detalle. Para estas consultas no aporta un acceso nuevo ni evita una operación observada. Agregaría entradas, WAL y espacio en cada alta. No se atribuye una medición a un índice que no se creó: el descarte se fundamenta en las definiciones existentes y esta carga.

## B. Vistas y equivalencia

| Vista | Vigencia e información expuesta | Filas normales | Con bordes |
|---|---|---:|---:|
| tp5_productos_vigentes | Producto y categoría activos; id, nombre, precio, stock y categoría | 45.002 | 45.003 |
| tp5_pedidos_clientes | Todos los estados; pedido e identificación/nombre/apellido del cliente, sin contacto | 200.004 | 200.007 |
| tp5_detalles_productos | Historia sin filtro de activo/estado; producto, cantidad, precio de venta y subtotal | 600.000 | 600.004 |

Para cada vista se ejecutó su consulta de referencia de [referencias_vistas.sql](referencias_vistas.sql): **EXCEPT ALL en ambos sentidos dio cero**, y la comparación completa de filas con el mismo ORDER BY dio igualdad. EXCEPT ALL detecta diferencias de multiplicidad; el orden pertenece a la consulta consumidora, no se garantiza por CREATE VIEW. Las referencias se elaboraron con Codex: no se presentan como consultas de autoría personal sin asistencia. La página 4 pide la consulta escrita por el estudiante; esa elaboración personal no se sustituye con la verificación automática.

Bordes ensayados y revertidos: producto vigente, categoría inactiva, baja de producto posterior a una venta, precio histórico 17 distinto del actual 100, pedido entregado, cancelado y pendiente sin líneas. Solo el producto con ambas vigencias apareció en V1; V2 conservó los tres estados; V3 conservó tres subtotales de 34 y uno de 8, incluidas bajas/cancelación, y cero líneas para el pedido vacío.

### Permisos de la vista de pedidos/clientes

Se creó un rol NOLOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE y NOINHERIT, sin membresías. Solo recibió USAGE del esquema y SELECT sobre `tp5_pedidos_clientes`. Bajo SET LOCAL ROLE se verificó:

- SELECT de la vista: 200.004 filas, permitido.
- SELECT directo de cliente y pedido: ambos rechazados con SQLSTATE `42501`.
- Solicitar correo_electronico o nro_telefono a la vista: rechazado con `42703`, porque esas columnas no se exponen.

Se usó el comportamiento predeterminado de las vistas: los permisos sobre las tablas se comprueban para el propietario de la vista; no se activó security_invoker. El rol y los GRANT se revirtieron y se comprobó su desaparición. No se instaló un usuario permanente ni se otorgó acceso público. El modelo **no almacena contraseñas**; la adaptación protege correo/teléfono existentes y prueba el mecanismo de acceso restringido, sin fingir la existencia de otra columna. No es aislamiento de filas por cliente. [Permisos de CREATE VIEW en PostgreSQL](https://www.postgresql.org/docs/17/sql-createview.html).

## C. Facturación materializada

Se reutilizó A1 del TP4 y se amplió a todos los meses. La regla sigue siendo ENTREGADO y catálogo vigente. `mes` se calcula en UTC; incluye enero de 2026 porque algunas fechas de la carga previa se desplazan al sumar segundos. No se corrigen esos datos silenciosamente ni se limita el reporte a 2025.

`tp5_facturacion_mensual` se creó WITH DATA y devolvió 39 filas iguales al reporte original. Tiene un índice UNIQUE B-tree sobre `(id_categoria,mes)`, de columnas simples y sin predicado; la agrupación y los NOT NULL de origen garantizan una fila por clave. Permite REFRESH CONCURRENTLY sobre una materialización ya poblada. [Requisitos oficiales de REFRESH](https://www.postgresql.org/docs/17/sql-refreshmaterializedview.html).

| Lectura | Mediana ms | Mín.–máx. ms |
|---|---:|---:|
| Agregación original sobre tablas, con índices heredados/nuevos | 217,223 | 213,484–272,534 |
| SELECT de la materializada, mismo orden | 0,024 | 0,023–0,040 |

La diferencia se explica por consultar 39 filas precalculadas frente a recorrer/unir/agrupar las ventas. No se sumó el costo del REFRESH a cada lectura, porque es una tarea periódica distinta. [Plan original](evidencias/20260922_194616/reporte_original.txt) y [plan materializado](evidencias/20260922_194616/reporte_materializado.txt). El Seq Scan sobre una materialización de 39 filas es apropiado: no toda lectura secuencial necesita otro índice.

Se ejecutó REFRESH MATERIALIZED VIEW CONCURRENTLY: 324,518 ms en la comprobación del índice y 338,412 ms en el caso con venta nueva. Son duraciones individuales de comando vistas por el cliente, no medianas ni mediciones de lectores concurrentes. La MV ocupa 8.192 bytes y su índice 16.384 al terminar.

Prueba de frescura: dentro de una transacción, una venta entregada nueva aportó 34 al reporte original mientras la MV conservó intactas sus 39 filas. Después del REFRESH CONCURRENTLY, apareció la nueva categoría/mes, con importe 34: 40 filas y cero diferencias contra el original. ROLLBACK restituyó datos y contenido materializado; se verificaron conteos y snapshot original.

Política propuesta para un tablero consultado cada minuto: refrescar cada **15 minutos**, y además después del cierre mensual. Entre refrescos, una nueva entrega, cambio de categoría o baja del catálogo no se refleja todavía. Una consulta usa el último estado materializado disponible. Con refrescos exitosos, la demora esperada es aproximadamente el intervalo más la duración del refresco; si falla la tarea, no hay un límite garantizado. Monitorear externamente la hora del último éxito y evitar ejecuciones superpuestas.

El refresco vuelve a calcular el agregado; no es incremental. CONCURRENTLY permite mantener lecturas durante el reemplazo pero no vuelve instantánea la actualización. La programación es una política documentada, **no se instaló un servicio automático**. El comando a programar, con un rol autorizado, es:

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY tp5_facturacion_mensual;
```

Una baja de producto/categoría cambia este agregado al refrescar porque conserva la semántica de A1: es facturación asociada al catálogo vigente, no un libro contable histórico inmutable.
