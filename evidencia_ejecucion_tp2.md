# Evidencia real de ejecución - TP2 Food Store

Fecha: 17/09/2026. Base de trabajo: `food_store_tp2` en PostgreSQL local. La base original no fue modificada.

## Esquema y datos de prueba

Se aplicó `schema.sql` y se verificó la existencia de las cinco tablas: `categoria`, `cliente`, `producto`, `pedido` y `detalle_pedido`.

Se cargaron dos productos de prueba, uno activo con stock 10 y otro inactivo; un cliente; y dos pedidos en estado `PENDIENTE`.

## Restricciones - resultados observados

La transición válida `PENDIENTE -> CONFIRMADO` afectó una fila. Las pruebas inválidas produjeron estos mensajes:

```text
ERROR: Transición de estado no permitida: CONFIRMADO -> PENDIENTE
ERROR: No se puede editar el detalle del pedido 1 porque está CONFIRMADO
ERROR: El producto 2 está inactivo
ERROR: Stock insuficiente para el producto 1: solicitado 999999, disponible 10
```

La inserción válida de un detalle en el pedido 2 con un producto activo y cantidad 1 fue aceptada. Todas las pruebas se ejecutaron dentro de una transacción y finalizaron con `ROLLBACK`.

## Escenario 1 - Lectura no repetible

Con Sesión A en `READ COMMITTED`, se obtuvo:

```text
primera_lectura: 10
segunda_lectura: 11
```

Entre ambas lecturas, Sesión B ejecutó `UPDATE producto SET stock = stock + 1 WHERE id_producto = 1` y confirmó. La lectura no repetible quedó demostrada.

Al repetir con Sesión A en `REPEATABLE READ`, se obtuvo:

```text
primera_lectura: 11
segunda_lectura: 11
```

Sesión B volvió a actualizar y confirmó, pero A mantuvo su snapshot. La explicación de la IA se confirmó.

## Escenario 2 - Lectura fantasma

Con Sesión A en `READ COMMITTED`, se obtuvo:

```text
primer_conteo: 2
segundo_conteo: 3
```

Entre ambos conteos, Sesión B insertó un pedido para el mismo cliente y confirmó. La nueva fila pasó a cumplir el `WHERE cliente_id = 1`, por lo cual la lectura fantasma quedó demostrada. La solución a verificar adicionalmente es repetir con `REPEATABLE READ`, donde A conserva su snapshot.

## Escenario 3 - Espera por bloqueo

Sesión A ejecutó `SELECT ... FOR UPDATE` sobre `producto.id_producto = 1` y mantuvo la transacción abierta. Sesión B intentó el mismo `FOR UPDATE` y quedó esperando aproximadamente **2,54 segundos**, hasta que A confirmó.

Al repetir con `FOR UPDATE NOWAIT` en B, PostgreSQL devolvió inmediatamente:

```text
ERROR: no se pudo bloquear un “lock” en la fila de la relación «producto»
```

La explicación de la IA se confirmó: el mecanismo que evita la espera es `NOWAIT`; el bloqueo se libera cuando la sesión que lo tomó hace `COMMIT` o `ROLLBACK`.

## Conclusión

Se reprodujeron tres escenarios exigidos por la consigna y se verificaron contra el motor PostgreSQL real. `REPEATABLE READ` evitó la lectura no repetible y el bloqueo de fila fue observado y comprobado con `NOWAIT`.
