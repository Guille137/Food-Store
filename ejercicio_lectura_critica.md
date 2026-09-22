# Parte 3 - Ejercicio de lectura crítica

## Script 1

```sql
UPDATE funcion
SET activa = FALSE;
```

### Qué filas afecta realmente

Actualiza **todas** las filas de `funcion`, incluidas las funciones que siguen en cartel y las que ya estaban inactivas. No tiene cláusula `WHERE`.

### Por qué no cumple la consigna

La consigna pide dar de baja sólo las funciones retiradas de cartel. El script no identifica retiro, vencimiento ni fecha; por eso desactiva indiscriminadamente toda la cartelera.

### Versión corregida

Suponiendo que la fecha de finalización se guarda en `fecha_fin`, una versión segura es:

```sql
UPDATE funcion
SET activa = FALSE
WHERE activa = TRUE
  AND fecha_fin < CURRENT_DATE;
```

Antes de actualizar se debe comprobar que el nombre y semántica de la columna sean los del esquema real. Primero conviene ejecutar el mismo `WHERE` con `SELECT *` dentro de una transacción.

## Script 2

```sql
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);
```

### Qué filas afecta realmente

En el esquema genérico, si `producto.categoria_id` no tiene valores `NULL`, elimina las categorías cuyo id no aparece en productos. Si la subconsulta devuelve un `NULL`, las categorías que sí tienen coincidencia producen `FALSE` y las que no tienen coincidencia producen `UNKNOWN`: ninguna cumple el WHERE. En Food Store la clave se llama `id_categoria`; el script literal con `id` daría un error de columna inexistente.

### Por qué no cumple la consigna de forma segura

No trata explícitamente los `NULL`. El resultado depende de un detalle de lógica ternaria de SQL y podría no borrar ninguna categoría aunque existan categorías sin productos. Además, debe respetar las claves foráneas del esquema real.

### Versión corregida

`NOT EXISTS` expresa directamente la condición y no se rompe por `NULL`:

```sql
DELETE FROM categoria AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM producto AS p
    WHERE p.categoria_id = c.id
);
```

La corrección anterior conserva el esquema genérico de la consigna. En Food Store, `producto.categoria_id` es `NOT NULL`, por lo que allí no se presenta el caso NULL. Además, la regla R7 exige baja lógica. La adaptación al proyecto sería:

```sql
UPDATE categoria AS c
SET activo = FALSE
WHERE c.activo = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM producto AS p WHERE p.categoria_id = c.id_categoria
  );
```

## Verificación realizada

`pruebas_lectura_critica.sql` reproduce el esquema genérico con tablas temporales. En PostgreSQL se observaron estos resultados:

- UPDATE sin WHERE: 3 funciones afectadas.
- UPDATE corregido: 1 función afectada; la función vigente sigue activa.
- NOT IN con NULL en la subconsulta: 0 categorías eliminadas.
- NOT EXISTS: 2 categorías sin productos eliminadas; se conserva la referenciada.

Las pruebas terminaron con ROLLBACK. `fecha_fin` es un supuesto explícito del esquema genérico de funciones, que no pertenece a Food Store. La adaptación de baja lógica se presenta como propuesta de diseño; los resultados anteriores corresponden al ejercicio genérico. Las salidas completas están en [la evidencia](evidencia_ejecucion_tp2.md).
