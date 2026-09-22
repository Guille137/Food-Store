# Parte 4 — Especificaciones antes de generar SQL

## Resumen por categoría

Tablas: categoria y producto. Devolver todas las categorías con categoria.activo=TRUE, incluidas las que no tengan productos vigentes. Contar solo producto.activo=TRUE. Columnas exactas: id_categoria, nombre, cantidad_productos. El conteo debe ser 0 si no hay productos vigentes. Ordenar por cantidad_productos DESC y luego id_categoria ASC; sin LIMIT ni HAVING. No usar SELECT *.

## Subconsulta de productos sin ventas vigentes

Tablas: producto, categoria, detalle_pedido y pedido. Devolver los productos activos de categorías activas que no tengan ninguna línea en pedidos cuyo estado sea distinto de CANCELADO. Un pedido cancelado no cuenta como venta vigente; los pedidos pendientes, confirmados y entregados sí cuentan a los efectos de esta consulta. Columnas: id_producto, nombre, precio_lista. Ordenar por id_producto ASC, sin LIMIT. No usar SELECT * y expresar la primera solución con NOT EXISTS.

Se solicitará una segunda versión con estructura distinta: preagregación frente a LEFT JOIN para el resumen, y antijoin contra productos de pedidos no cancelados frente a NOT EXISTS para la subconsulta.

## Comprobación

Comparar ambas direcciones con EXCEPT ALL, contar filas y verificar el orden de la lista completa. Probar sobre la carga masiva y sobre casos agregados dentro de una transacción: categoría sin productos, categoría con un único producto inactivo, categoría inactiva, producto sin pedidos, producto presente solo en pedido cancelado y producto con un pedido vigente. Terminar con ROLLBACK.
