# Informe de concurrencia — Food Store

Ejecución real: 22/09/2026, PostgreSQL 17.11 sobre Windows. Se utilizaron dos conexiones independientes de psycopg 3.3.6 y una conexión observadora para los bloqueos. No se simularon respuestas del motor.

Cada escenario parte de una copia nueva de la base con `schema.sql`, `datos_iniciales.sql` y `restricciones_Food_Store.sql`: producto 1 con stock 10, cliente 1 y tres pedidos pendientes. El ejecutor es `verificar_tp2.py`; el protocolo de copia, transacción y respaldo está en `protocolo_seguridad.md`.

Las explicaciones siguientes se conservan textualmente del informe anterior generado con IA. La ejecución actual las contrasta con el motor. Los registros muestran resultados de consultas como listas de filas y las escrituras como etiquetas de PostgreSQL, por ejemplo `UPDATE 1`.

## Escenario 1 — Lectura no repetible

### Secuencia y resultados observados

A abre READ COMMITTED y lee stock 10. B incrementa el stock y confirma; A vuelve a leer y obtiene 11. En una copia nueva se repite con A en REPEATABLE READ: ambas lecturas devuelven 10.

### Explicación de la IA (texto conservado)

En PostgreSQL con `READ COMMITTED`, cada sentencia ve los datos confirmados al comienzo de esa sentencia. Por eso dos `SELECT` iguales dentro de una misma transacción pueden devolver valores distintos si otra transacción confirma una actualización entre ambos. `REPEATABLE READ` mantiene un snapshot consistente para la transacción y evita esa lectura no repetible.

### Verificación en el motor

**lectura_rc_A**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_lectura_rc", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**lectura_rc_B**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_lectura_rc", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**lectura_rc_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**lectura_rc_B**

```sql
UPDATE producto SET stock=stock+1 WHERE id_producto=1
```

```text
"UPDATE 1"
```

**lectura_rc_B**

```sql
ROLLBACK
```

```text
"ROLLBACK"
```

**lectura_rc_A**

```sql
BEGIN ISOLATION LEVEL READ COMMITTED
```

```text
"BEGIN"
```

**lectura_rc_A**

```sql
SELECT stock FROM producto WHERE id_producto=1
```

```text
[[10]]
```

**lectura_rc_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**lectura_rc_B**

```sql
UPDATE producto SET stock=stock+1 WHERE id_producto=1
```

```text
"UPDATE 1"
```

**lectura_rc_B**

```sql
COMMIT
```

```text
"COMMIT"
```

**lectura_rc_A**

```sql
SELECT stock FROM producto WHERE id_producto=1
```

```text
[[11]]
```

**lectura_rc_A**

```sql
COMMIT
```

```text
"COMMIT"
```

**lectura_rr_A**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_lectura_rr", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**lectura_rr_B**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_lectura_rr", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**lectura_rr_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**lectura_rr_B**

```sql
UPDATE producto SET stock=stock+1 WHERE id_producto=1
```

```text
"UPDATE 1"
```

**lectura_rr_B**

```sql
ROLLBACK
```

```text
"ROLLBACK"
```

**lectura_rr_A**

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ
```

```text
"BEGIN"
```

**lectura_rr_A**

```sql
SELECT stock FROM producto WHERE id_producto=1
```

```text
[[10]]
```

**lectura_rr_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**lectura_rr_B**

```sql
UPDATE producto SET stock=stock+1 WHERE id_producto=1
```

```text
"UPDATE 1"
```

**lectura_rr_B**

```sql
COMMIT
```

```text
"COMMIT"
```

**lectura_rr_A**

```sql
SELECT stock FROM producto WHERE id_producto=1
```

```text
[[10]]
```

**lectura_rr_A**

```sql
COMMIT
```

```text
"COMMIT"
```

### Conclusión

La explicación se confirmó: READ COMMITTED permite la lectura no repetible; REPEATABLE READ mantuvo el valor inicial durante la transacción.

## Escenario 2 — Lectura fantasma

### Secuencia y resultados observados

A cuenta 3 pedidos del cliente 1 en READ COMMITTED. B inserta un pedido y confirma; A obtiene 4. En otra copia, con REPEATABLE READ, A obtiene 3 y 3 aunque B confirma su inserción.

### Explicación de la IA (texto conservado)

La lectura fantasma ocurre cuando una consulta por condición se repite y aparecen o desaparecen filas que cumplen el `WHERE` por un `INSERT` o `DELETE` concurrente confirmado. En PostgreSQL, `READ COMMITTED` permite esa variación entre sentencias. `REPEATABLE READ` usa el mismo snapshot de A y evita que la nueva fila aparezca en su segundo `COUNT`.

### Verificación en el motor

**fantasma_rc_A**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_fantasma_rc", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**fantasma_rc_B**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_fantasma_rc", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**fantasma_rc_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**fantasma_rc_B**

```sql
INSERT INTO pedido (forma_pago,cliente_id) VALUES ('EFECTIVO',1)
```

```text
"INSERT 0 1"
```

**fantasma_rc_B**

```sql
ROLLBACK
```

```text
"ROLLBACK"
```

**fantasma_rc_A**

```sql
BEGIN ISOLATION LEVEL READ COMMITTED
```

```text
"BEGIN"
```

**fantasma_rc_A**

```sql
SELECT count(*) FROM pedido WHERE cliente_id=1
```

```text
[[3]]
```

**fantasma_rc_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**fantasma_rc_B**

```sql
INSERT INTO pedido (forma_pago,cliente_id) VALUES ('EFECTIVO',1)
```

```text
"INSERT 0 1"
```

**fantasma_rc_B**

```sql
COMMIT
```

```text
"COMMIT"
```

**fantasma_rc_A**

```sql
SELECT count(*) FROM pedido WHERE cliente_id=1
```

```text
[[4]]
```

**fantasma_rc_A**

```sql
COMMIT
```

```text
"COMMIT"
```

**fantasma_rr_A**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_fantasma_rr", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**fantasma_rr_B**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_fantasma_rr", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**fantasma_rr_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**fantasma_rr_B**

```sql
INSERT INTO pedido (forma_pago,cliente_id) VALUES ('EFECTIVO',1)
```

```text
"INSERT 0 1"
```

**fantasma_rr_B**

```sql
ROLLBACK
```

```text
"ROLLBACK"
```

**fantasma_rr_A**

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ
```

```text
"BEGIN"
```

**fantasma_rr_A**

```sql
SELECT count(*) FROM pedido WHERE cliente_id=1
```

```text
[[3]]
```

**fantasma_rr_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**fantasma_rr_B**

```sql
INSERT INTO pedido (forma_pago,cliente_id) VALUES ('EFECTIVO',1)
```

```text
"INSERT 0 1"
```

**fantasma_rr_B**

```sql
COMMIT
```

```text
"COMMIT"
```

**fantasma_rr_A**

```sql
SELECT count(*) FROM pedido WHERE cliente_id=1
```

```text
[[3]]
```

**fantasma_rr_A**

```sql
COMMIT
```

```text
"COMMIT"
```

### Conclusión

La explicación se confirmó también en la repetición que faltaba: REPEATABLE READ conservó el conteo y evitó la lectura fantasma en PostgreSQL.

## Escenario 3 — Espera por bloqueo

### Secuencia y resultados observados

A toma FOR UPDATE sobre producto 1. B inicia otra transacción e intenta tomar el mismo bloqueo. La conexión observadora comprueba wait_event_type=Lock antes de que A confirme; entonces B continúa. Se repite con NOWAIT y B recibe SQLSTATE 55P03 sin esperar a que A libere la fila.

La duración medida desde que se lanzó B hasta obtener su resultado fue 0.016 segundos. Se sincronizó por la espera real del motor, sin imponer una pausa artificial. En el registro, el SELECT de B aparece al finalizar; su inicio ocurre antes del COMMIT de A, como muestra el ejecutor.

### Explicación de la IA (texto conservado)

`FOR UPDATE` toma un bloqueo de fila que impide que otra transacción tome un bloqueo incompatible sobre esa misma fila. La segunda sesión espera hasta que la primera confirme o revierta. No se resuelve cambiando el nivel de aislamiento: se resuelve liberando el bloqueo pronto, usando un orden coherente de toma de filas o, cuando corresponde, `NOWAIT`/`SKIP LOCKED`.

### Verificación en el motor

**bloqueo_A**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_bloqueo", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**bloqueo_B**

```sql
SELECT current_database(), current_user, version()
```

```text
[["food_store_tp2_20260922_135107_303493_bloqueo", "postgres", "PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit"]]
```

**bloqueo_A**

```sql
BEGIN
```

```text
"BEGIN"
```

**bloqueo_A**

```sql
SELECT id_producto FROM producto WHERE id_producto=1 FOR UPDATE
```

```text
[[1]]
```

**bloqueo_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**bloqueo_A**

```sql
COMMIT
```

```text
"COMMIT"
```

**bloqueo_B**

```sql
SELECT id_producto FROM producto WHERE id_producto=1 FOR UPDATE
```

```text
[[1]]
```

**bloqueo_B**

```sql
COMMIT
```

```text
"COMMIT"
```

**bloqueo_A**

```sql
BEGIN
```

```text
"BEGIN"
```

**bloqueo_A**

```sql
SELECT id_producto FROM producto WHERE id_producto=1 FOR UPDATE
```

```text
[[1]]
```

**bloqueo_B**

```sql
BEGIN
```

```text
"BEGIN"
```

**bloqueo_B**

```sql
SELECT id_producto FROM producto WHERE id_producto=1 FOR UPDATE NOWAIT
```

```text
{"sqlstate": "55P03", "mensaje": "could not obtain lock on row in relation \"producto\""}
```

**bloqueo_B**

```sql
ROLLBACK
```

```text
"ROLLBACK"
```

**bloqueo_A**

```sql
ROLLBACK
```

```text
"ROLLBACK"
```

### Conclusión

La espera se observó en pg_stat_activity y terminó al confirmar A. NOWAIT sustituyó la espera por un error que la aplicación debe manejar; no concede acceso a la fila bloqueada. La explicación se confirmó.

## Regresiones adicionales

También se verificó el bloqueo del pedido al editar detalles en ambos órdenes: una confirmación espera si hay una edición abierta; una inserción espera si se está confirmando y, tras el COMMIT, falla con 23514. Se documenta en la evidencia y en la DUIA de la Parte 1.

## Fuentes y trazabilidad

- [Registro íntegro de esta ejecución](evidencias/ejecucion_20260922_135107_303493.json).
- [Declaración de uso de IA](duia_partes2y3.md).
- [Aislamiento en PostgreSQL](https://www.postgresql.org/docs/17/transaction-iso.html).
- [Bloqueos explícitos en PostgreSQL](https://www.postgresql.org/docs/17/explicit-locking.html).

No se realizó el interbloqueo opcional; los tres escenarios obligatorios elegidos están comprobados.
