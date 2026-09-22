# Reportes analíticos — especificación del laboratorio

Se continúa la base masiva de la Semana 3 con sus índices y restricciones. En el modelo propio, usuario corresponde a cliente; pedido no tiene total almacenado: se calcula con cantidad × precio_unitario del detalle. Cliente, pedido y detalle_pedido no tienen marca de baja lógica. Producto y categoria usan activo. Estas correspondencias evitan inventar columnas del ejemplo docente.

## A1 — Facturación por categoría en junio de 2025

Tablas: pedido, detalle_pedido, producto y categoria. Incluir solo pedidos ENTREGADO cuya fecha civil UTC esté en junio de 2025, productos activos y categorías activas. La vigencia del catálogo se evalúa al consultar; no se presenta como facturación histórica de productos dados de baja. Agrupar por id y nombre de categoría y mes UTC. Salida: id_categoria, nombre, mes (DATE), unidades (suma de cantidad) e importe (suma exacta NUMERIC de cantidad × precio_unitario). Ordenar por mes e id_categoria. Sin LIMIT; categorías sin ventas calificantes no aparecen.

## A2 — Ranking de clientes por gasto entregado en 2025

Tablas: cliente, pedido y detalle_pedido (dos JOIN). Incluir solo pedidos ENTREGADO en el año civil UTC 2025 y clientes con al menos una línea de esos pedidos. Contabilizar todas las líneas históricas, aunque luego un producto o categoría se haya dado de baja; el reporte no une el catálogo porque no necesita sus atributos. No hay marcas de baja lógica en las tres tablas involucradas.

Salida: id_cliente, nombre, apellido y total_gastado NUMERIC. Orden descendente por total_gastado y ascendente por id_cliente como desempate. Devolver 50 filas. Este ranking agregado se usa también como ejemplo de la competencia de la Parte 4, con la misma consulta, datos y condiciones en cada estrategia.

## Medición

Elegir reescrituras e índices solo después de leer los planes iniciales. Identificar cada join por sus entradas, no solo por una lista de algoritmos. Conservar índices del TP3, mantener parámetros del optimizador y medir con un calentamiento y cinco planes completos por etapa. Comparar mediana de Execution Time, no cost. Comprobar equivalencia de resultados y orden antes de aceptar una optimización.
