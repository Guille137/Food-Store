# Guía de escenarios C2–C6 en PostgreSQL

Ejecutar solo en una copia de pruebas, creada desde el esquema y seed sintético de Food Store. No aplicar estos cambios a una base compartida o productiva. Confirmar primero `SELECT current_database(), current_user;`.

## Preparación

1. Instalar el esquema, las restricciones y `datos_iniciales.sql` en una base nueva. El seed define producto 1 a $1000 con stock 10, producto 3 a $900 con stock 5 y ambos activos.
2. Crear la vista con `snapshot_postgresql.sql`.
3. Anotar antes de cada simulación los controles:

   ```sql
   SELECT count(*) AS pedidos FROM pedido;
   SELECT COALESCE(sum(stock), 0) AS stock_total FROM producto;
   ```

4. Exportar la vista, eliminando primero la instantánea previa en SQLite y luego importando el nuevo CSV:

   ```sql
   \copy (SELECT * FROM v_snapshot_movil ORDER BY id) TO 'servidor_snapshot.csv' CSV HEADER
   ```

   En SQLite, `DELETE FROM snapshot_servidor;` y `.import --csv --skip 1 servidor_snapshot.csv snapshot_servidor`. Después, `.read cargar_cache.sql` y `.read semaforo.sql`.

## Escenarios

| Caso | Acción en la copia PostgreSQL | En SQLite y resultado esperado |
|---|---|---|
| C2 | Crear borrador por producto 1 a 100000 centavos. `UPDATE producto SET precio_lista=1100 WHERE id_producto=1;` Exportar snapshot. | La primera solicitud queda `CONFLICTO`. Aceptar el nuevo precio (110000 centavos) en el borrador y crear una solicitud con UUID nuevo; al comparar de nuevo, queda `SIMULADO_APROBADO`. |
| C3 | No modificar stock del producto 1; verificar que sigue en 10. Exportar snapshot actualizado. | Borrador de 11 unidades; queda `RECHAZADO` por stock insuficiente. |
| C4 | Crear borrador por producto 1 y ejecutar `UPDATE producto SET activo=false WHERE id_producto=1;`. Exportar snapshot. | La solicitud queda `RECHAZADO`. La fila continúa en `snapshot_servidor` con `eliminado=t`; tras `cargar_cache.sql` no aparece en catálogo disponible, aunque `producto_cache` conserva su fila. |
| C5 | Sin cambios sobre producto 3 (precio 900, stock 5, activo). Exportar snapshot. | Borrador de 2 unidades; queda `SIMULADO_APROBADO`, nunca como venta. |
| C6 | No requiere cambios en PostgreSQL. | Enviar dos veces el mismo UUID de solicitud: la segunda inserción local falla por PK; volver a ejecutar el semáforo no reevalúa una fila ya resuelta. Un receptor real también debe persistir la clave idempotente. |

Después de cada ejecución del semáforo, volver a consultar los dos controles y registrar los valores observados. La cantidad de pedidos y el stock total deben coincidir con sus valores inmediatamente anteriores a esa simulación. Las modificaciones intencionales del precio en C2 y de `activo` en C4 preparan el conflicto y la lápida en la copia; no son cambios hechos por la tablet.

## UUID de ejemplo

El script `movil/pruebas_casos_sqlite.sql` usa UUID determinísticos válidos solo para las filas locales: borradores en el rango `60000000-...` y solicitudes en `80000000-...`. No están asociados a usuarios reales.
