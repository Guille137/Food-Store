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

Si `producto.categoria_id` no tiene valores `NULL`, elimina las categorías cuyo id no aparece en productos. Si la subconsulta devuelve aunque sea un `NULL`, la comparación `id NOT IN (...)` resulta `UNKNOWN` para cada fila y no elimina ninguna categoría.

### Por qué no cumple la consigna de forma segura

No trata explícitamente los `NULL`. El resultado depende de un detalle de lógica ternaria de SQL y podría no borrar ninguna categoría aunque existan categorías sin productos. Además, debe respetar las claves foráneas del esquema real.

### Versión corregida

`NOT EXISTS` expresa directamente la condición y no se rompe por `NULL`:

```sql
DELETE FROM categoria AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM producto AS p
    WHERE p.categoria_id = c.id_categoria
);
```

En el esquema Food Store provisto, `producto.categoria_id` es `NOT NULL`, pero `NOT EXISTS` sigue siendo más claro y robusto. La sentencia se prueba primero con `ROLLBACK` y con un respaldo previo.
