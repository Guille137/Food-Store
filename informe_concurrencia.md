# Parte 2 - Informe de concurrencia: Food Store

> Importante: los bloques de comandos están listos para ejecutar en dos conexiones `psql` sobre una **copia** de la base. La salida debe pegarse al ejecutar; no se inventan resultados. En PostgreSQL, `READ COMMITTED` es el aislamiento predeterminado.

## Datos mínimos de preparación

En una sesión aparte, elegir un producto existente con `id_producto = 1` y dos pedidos existentes con `id_pedido = 1` y `id_pedido = 2`. Si esos ids no existen, reemplazarlos en todos los bloques. Para el escenario de fantasma se usará el cliente `id_cliente = 1`, que también debe existir.

## Escenario 1 - Lectura no repetible

### Cómo se reproduce

| Orden | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN ISOLATION LEVEL READ COMMITTED;` | |
| 2 | `SELECT id_producto, stock FROM producto WHERE id_producto = 1;` | |
| 3 | | `BEGIN; UPDATE producto SET stock = stock + 1 WHERE id_producto = 1; COMMIT;` |
| 4 | `SELECT id_producto, stock FROM producto WHERE id_producto = 1; COMMIT;` | |

### Qué se observó

Pegar la salida real aquí. Con `READ COMMITTED`, la segunda consulta de A debe poder ver el valor confirmado por B porque cada sentencia toma un snapshot nuevo.

### Explicación de la IA

En PostgreSQL con `READ COMMITTED`, cada sentencia ve los datos confirmados al comienzo de esa sentencia. Por eso dos `SELECT` iguales dentro de una misma transacción pueden devolver valores distintos si otra transacción confirma una actualización entre ambos. `REPEATABLE READ` mantiene un snapshot consistente para la transacción y evita esa lectura no repetible.

### Verificación en el motor

Repetir cambiando el primer comando de A por:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
```

La segunda consulta de A debe conservar el mismo valor que la primera, aun después del `COMMIT` de B. Pegar la salida real aquí.

### Conclusión

Completar después de la prueba: indicar si PostgreSQL confirmó la explicación y registrar que `REPEATABLE READ` evitó el cambio observado por A.

## Escenario 2 - Lectura fantasma

### Cómo se reproduce

| Orden | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN ISOLATION LEVEL READ COMMITTED;` | |
| 2 | `SELECT COUNT(*) FROM pedido WHERE cliente_id = 1;` | |
| 3 | | `INSERT INTO pedido (forma_pago, cliente_id) VALUES ('EFECTIVO', 1); COMMIT;` |
| 4 | `SELECT COUNT(*) FROM pedido WHERE cliente_id = 1; COMMIT;` | |

### Qué se observó

Pegar la salida real aquí. En `READ COMMITTED`, el segundo `COUNT` debe incluir la fila confirmada por B y, por lo tanto, ser mayor en uno.

### Explicación de la IA

La lectura fantasma ocurre cuando una consulta por condición se repite y aparecen o desaparecen filas que cumplen el `WHERE` por un `INSERT` o `DELETE` concurrente confirmado. En PostgreSQL, `READ COMMITTED` permite esa variación entre sentencias. `REPEATABLE READ` usa el mismo snapshot de A y evita que la nueva fila aparezca en su segundo `COUNT`.

### Verificación en el motor

Repetir con A en `BEGIN ISOLATION LEVEL REPEATABLE READ;`. El `INSERT` de B puede confirmar, pero el segundo `COUNT` de A debe coincidir con el primero. Pegar la salida real aquí.

### Conclusión

Completar con los dos conteos observados y si se confirmó la explicación.

## Escenario 3 - Espera por bloqueo

### Cómo se reproduce

| Orden | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` | |
| 2 | `SELECT id_producto, stock FROM producto WHERE id_producto = 1 FOR UPDATE;` | |
| 3 | | `BEGIN; SELECT id_producto, stock FROM producto WHERE id_producto = 1 FOR UPDATE;` |
| 4 | Mantener la transacción abierta unos segundos y luego ejecutar `COMMIT;` | La consulta queda esperando y continúa después del `COMMIT` de A; luego ejecutar `COMMIT;`. |

### Qué se observó

Pegar el momento en que B quedó esperando y la salida obtenida después del `COMMIT` de A. También puede capturarse desde una tercera sesión con:

```sql
SELECT pid, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE datname = current_database() AND wait_event_type IS NOT NULL;
```

### Explicación de la IA

`FOR UPDATE` toma un bloqueo de fila que impide que otra transacción tome un bloqueo incompatible sobre esa misma fila. La segunda sesión espera hasta que la primera confirme o revierta. No se resuelve cambiando el nivel de aislamiento: se resuelve liberando el bloqueo pronto, usando un orden coherente de toma de filas o, cuando corresponde, `NOWAIT`/`SKIP LOCKED`.

### Verificación en el motor

Repetir con `FOR UPDATE NOWAIT` en B:

```sql
SELECT id_producto, stock FROM producto WHERE id_producto = 1 FOR UPDATE NOWAIT;
```

Debe fallar inmediatamente con un error de bloqueo en vez de esperar. Pegar la salida real aquí.

### Conclusión

Completar con la espera real observada y la comprobación de `NOWAIT`.
