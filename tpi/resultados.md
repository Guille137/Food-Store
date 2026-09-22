# Resultados verificables de la entrega integradora

Fecha: 22/09/2026. PostgreSQL 17.11 en Windows. Base nueva `food_store_tpi_20260922_204000_480700`. **79 comprobaciones correctas**, `exito: true`. [Registro completo con SQL, parámetros, salidas y errores esperados](evidencias/20260922_204000_480700/resultado.json). [Ejecutor reproducible](verificar_tpi.py).

Las 79 comprobaciones incluyen el ensayo del DDL y la ejecución definitiva; no se presentan como 79 reglas de negocio distintas. No se simularon resultados del motor.

## Instalación y objetos

Se instaló desde cero el esquema, seed, reglas anteriores, todos los índices de TP3–TP5, las tres vistas y la materializada. Después se agregaron cuatro rutinas nuevas: una función de total, dos procedimientos y una función de trigger, utilizada por dos triggers con tabla de transición. Junto con las tres funciones de trigger anteriores, el catálogo registra siete rutinas PL/pgSQL.

El primer ensayo del DDL se revirtió, se comprobó la ausencia de las rutinas nuevas y luego se crearon definitivamente. Los respaldos anteriores a cada bloque DDL permanecen en `backups/`, fuera de Git.

## Función, JSONB y atomicidad de CALL

| Caso | Resultado observado |
|---|---|
| Pedido con 2 unidades a 10 y 1 unidad a 25 | Dos detalles y total NUMERIC 45 |
| Pedido existente sin detalles | Total 0 |
| Pedido inexistente o NULL | P0002 |
| Error de stock en la segunda línea | 23514; no queda cabecera ni primera línea del CALL fallido |
| JSONB inválido, vacío, claves/tipos incorrectos, repetidos, cantidad fuera de INTEGER | 22023 en los 12 casos de datos y en la prueba de salida no nula |
| Cliente/producto inexistente | 23503 |
| Forma de pago NULL | 23502 |
| Baja repetida del mismo producto | Permitida; conserva activo=false y la fila |

El precio no lo proporciona el cliente en el JSONB: el procedimiento lo copia desde producto bajo bloqueo FOR SHARE. Stock mantiene la regla anterior por línea; no se decrementa ni se reserva. El CALL no ejecuta COMMIT interno: participa en la transacción de quien lo invoca.

## Restricciones y triggers

Se comprobaron CHECK de stock, precio de lista, cantidad y precio de venta (23514), FK de categoría (23503) y UNIQUE del nombre de producto (23505). Se rechazaron PENDIENTE → ENTREGADO, edición de un confirmado y salida de un estado terminal (23514); se aceptaron las transiciones intermedias válidas.

Los nuevos triggers `AFTER INSERT` y `AFTER UPDATE`, ambos `FOR EACH STATEMENT`, reciben `NEW TABLE AS nuevas_lineas`. Una sentencia válida de dos filas se acepta. Si una de las categorías está inactiva, un INSERT de dos filas no deja la primera insertada y un UPDATE de dos filas conserva ambos precios originales. El total del ejemplo se mantiene en 70 después del UPDATE rechazado. El error es 23514, manejado con SAVEPOINT.

La regla nueva valida categorías de las líneas incorporadas/editadas, sin eliminar ni modificar ventas anteriores cuando se da de baja una categoría. No se cambian las funciones previas del TP2.

## Borrado lógico

Prueba con pedido de total 45:

1. La consulta sobre `producto WHERE activo AND lower(nombre)=...` devuelve una fila.
2. Se modifica el precio actual a 999 y se invoca `CALL tpi_baja_producto(...)` dos veces.
3. La fila sigue existiendo, con activo=false; el catálogo vigente deja de mostrarla.
4. Los detalles históricos siguen exactamente iguales y la función sigue devolviendo 45.
5. Se rechaza una nueva venta de ese producto (23514), reutilizar su nombre (23505) y borrarlo físicamente mientras está referenciado (23503).

Antes y después, el plan usa **Bitmap Index Scan sobre `tp5_producto_nombre_activo` + Bitmap Heap Scan**, sin forzar el planificador. El resultado visible pasa de una fila a cero. Los planes completos están en `planes_baja` del JSON. MVCC puede conservar entradas físicas de versiones antiguas hasta su limpieza: no se afirma que el índice pierda inmediatamente toda referencia física al producto. Esta prueba acredita resultados correctos de baja, no una mejora de velocidad.

La categoría también tiene baja lógica: al poner activo=false, su producto queda fuera de `tp5_productos_vigentes` aunque producto.activo siga en TRUE. El historial y el total permanecen. El nuevo trigger impide registrar/editar líneas de esa categoría; las bajas no se propagan a los productos ni destruyen referencias.

El índice parcial de producto filtra **producto.activo**, no categoria.activo: un predicado del índice no consulta otra tabla. Por eso la vista añade el JOIN/filtro de categoría. Los reportes históricos no usan ese filtro cuando necesitan conservar ventas. La materializada heredada de A1 sí representa catálogo vigente y requiere REFRESH para reflejar cambios.

## COMMIT, ROLLBACK y dos conexiones

- Una conexión inserta el pedido; otra no lo ve antes de COMMIT y después puede consultar su total 45.
- Un segundo pedido se revierte: no quedan ni cabecera ni detalles en ninguna conexión.
- La conexión A desactiva una categoría sin confirmar. La conexión B intenta registrar una venta y queda bloqueada; la observadora verifica `pg_blocking_pids` no vacío.
- A confirma la baja. B continúa, detecta la categoría inactiva y recibe 23514. No queda un pedido parcial. Se restaura la categoría para conservar la base de inspección en estado activo.

Para los niveles de aislamiento se reutiliza la [evidencia real del TP2](../informe_concurrencia.md): lectura no repetible y fantasma en READ COMMITTED frente a REPEATABLE READ, y bloqueo con FOR UPDATE. No se atribuyen esos ensayos a esta nueva sesión.

## Vistas, refresco y estado final

Las tres vistas coinciden con sus referencias mediante EXCEPT ALL en ambos sentidos: `(0,0)`. El pedido que se confirmó con COMMIT se llevó por transiciones válidas a ENTREGADO y se ejecutó REFRESH MATERIALIZED VIEW CONCURRENTLY; el importe agregado resultó 45.

Conteos finales: 5 categorías, 4.005 productos, 1 cliente, 4 pedidos y 2 detalles. Hay 4.000 productos auxiliares y dos productos/categorías del caso de persistencia; los demás casos se revirtieron. Las secuencias pueden tener huecos por ensayos revertidos. No se modificaron las bases de los TP anteriores.

Esta instalación pequeña permite verificar funcionalidad de forma independiente. Los resultados de rendimiento sobre 600.000 detalles están en [TP3](../tp3/informe_optimizacion.md), [TP4](../tp4/informe_optimizacion.md) y [TP5](../tp5/informe_mediciones.md); se mantienen sus condiciones y muestras originales.
