# Especificaciones previas — índices

Contexto común: conservar esquema, restricciones e índices de TP2–TP4. PostgreSQL 17; 50.003 productos, 200.003 pedidos y 600.000 detalles. Las tres consultas exactas, incluidos proyección, filtros y orden, están en [queries.sql](../queries.sql), Q1, Q2 y Q3. Este archivo y las consultas se versionan antes de generar los índices.

Las frecuencias siguientes son supuestos de diseño de una aplicación Food Store, no telemetría de producción. El catálogo y el historial provienen del trabajo del TP3; el desglose de facturación continúa los reportes del TP4. Sus variantes ya optimizadas se conservan. Se amplía la carga con estos filtros, que todavía presentan Seq Scan en la copia heredada: no se quitan índices anteriores para fabricar una mejora.

## I1 — catálogo por nombre sin distinguir mayúsculas

- Consulta: Q1 completa de `queries.sql`. Frecuencia esperada: 60 búsquedas/minuto.
- Filtros: `activo` y `lower(nombre)`; sin JOIN ni ORDER BY. Exponer también stock y categoría.
- Proponer tipo, clave y posible predicado; considerar el UNIQUE existente sobre `nombre`, que no indexa `lower(nombre)`.
- Aceptación: mismos valores, desaparición del Seq Scan de producto, mediana de cinco ejecuciones calientes inferior a la inicial. No prometer un factor antes de medir.

## I2 — cola de confirmados con tarjeta

- Consulta: Q2 completa. Frecuencia esperada: una vez/minuto en el panel operativo.
- Filtros de igualdad sobre `estado` y `forma_pago`; ordenar por `fecha, id_pedido`; no hay JOIN.
- Proponer índice compuesto y condición parcial para la cola. Debe contemplar que los pedidos abandonan el índice al cambiar de estado. Evaluar cobertura de la proyección sin añadir tablas ni columnas.
- Aceptación: mismo conjunto y orden, Index/Bitmap en lugar de Seq Scan, mediana menor. Se permiten Index Only Scan como acceso por índice. Los literales de estado/pago de esta consulta son parte del contrato; no afirmar que todo plan genérico parametrizado podrá usar el índice parcial.

## I3 — auditoría de precios de venta

- Consulta: Q3 completa. Frecuencia esperada: 12 veces/hora. Precio histórico, no precio actual del catálogo.
- Rango sobre `precio_unitario`, orden por `precio_unitario,id_pedido,id_producto`; no hay JOIN.
- Proponer un B-tree que permita otros umbrales y conserve la cantidad en la lectura. Justificar su tamaño frente al beneficio; no añadir un segundo índice para la misma consulta.
- Aceptación: mismo conjunto/orden, Index/Bitmap en lugar del Seq Scan paralelo y mediana menor.
- Medir escritura: 800 líneas válidas en un pedido PENDIENTE, mismos productos, precios y cantidades, en copias antes/después. Un calentamiento y siete pares alternados; revertir cada carga. Informar tiempos, dispersión, WAL y alcance: ejecución del INSERT con triggers, sin latencia de COMMIT ni concurrencia. No inventar un sobrecosto positivo si hay ruido.

## Revisión de sobreindexación

Proponer y evaluar también un índice adicional sobre `detalle_pedido(id_pedido)`. Compararlo con la PK `(id_pedido,id_producto)` y con `tp4_detalle_pedido_cubierto`. Rechazarlo si no aporta un acceso nuevo para esta carga; no ejecutarlo para la entrega.
