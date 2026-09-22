# Especificación previa — facturación por categoría y mes

Origen: [A1 del TP4](../../tp4/a1_antes.sql). Extender de junio al conjunto de meses disponibles, conservando su semántica: pedidos ENTREGADO, producto y categoría activos. No presentarlo como facturación histórica inmutable: una baja del catálogo modifica este reporte tras refrescar.

Crear `tp5_facturacion_mensual` WITH DATA, con columnas `id_categoria,nombre_categoria,mes,unidades,importe`. Mes es DATE derivada de `fecha AT TIME ZONE 'UTC'` para no depender de la zona de la sesión. Agrupar por categoría y mes; sumas de cantidad y de cantidad*precio_unitario.

Crear después, en otro commit, un índice UNIQUE B-tree `(id_categoria,mes)`, sin expresión ni condición parcial, para REFRESH MATERIALIZED VIEW CONCURRENTLY. Son claves no nulas por el modelo de origen. No confiar en el orden físico de la materialización; ordenar cada consulta por mes,id_categoria.

Criterios: igualdad exacta de resultados con la consulta original; lectura mediana de cinco muestras menor que la agregación; inserción de una venta de prueba que deje temporalmente desactualizada la materialización, REFRESH CONCURRENTLY exitoso y recuperación de igualdad; ROLLBACK de toda esa prueba. Ensayar DDL antes de aplicarlo, con respaldo previo.

Uso esperado: tablero de gestión consultado cada minuto; tolera hasta quince minutos de demora después de un REFRESH exitoso, más su duración. Proponer refresco cada quince minutos y uno luego del cierre mensual; documentar que la programación no queda instalada y que una falla extiende indefinidamente la demora. Registrar la hora del último éxito en un sistema de monitoreo externo, no añadir columnas ni tablas al modelo. El REFRESH no es incremental y también consume recursos; medir una ejecución real.
