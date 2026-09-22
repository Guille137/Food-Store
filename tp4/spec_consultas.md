# Parte 3 — Especificaciones previas al SQL

## R: ranking con ventana

Tablas: cliente, pedido y detalle_pedido. No tienen columnas de baja lógica. Incluir clientes con al menos una línea de pedido ENTREGADO dentro de 2025 UTC, incluso si el gasto total es 0. Excluir pedidos sin detalles y estados distintos de ENTREGADO. El gasto histórico incluye líneas de productos/categorías que luego se desactivaron: no se une ese catálogo ni se cambia el importe histórico por el precio de lista actual.

Columnas exactas: id_cliente, nombre_completo (nombre, espacio y apellido), total_gastado NUMERIC y puesto BIGINT. Una fila por cliente. Ranking global sin PARTITION BY, mediante DENSE_RANK por total_gastado DESC: empates comparten puesto y el siguiente puesto no deja huecos. El id_cliente no entra en el ORDER BY de la ventana, porque rompería los empates. Orden de presentación: puesto ASC e id_cliente ASC. Sin LIMIT.

La alternativa debe conservar los empates con otra estructura: sumar primero por pedido, luego por cliente, numerar los importes distintos y unirlos con los clientes.

## C: subconsulta correlacionada

Mismas tablas, período, estado y política de bajas lógicas. Devolver clientes cuyo gasto total en líneas entregadas de 2025 UTC sea estrictamente mayor que 50.000. Columnas: id_cliente, nombre_completo y correo_electronico. Orden id_cliente ASC; sin LIMIT. Un cliente sin líneas calificantes no aparece; SUM devuelve NULL y no supera el umbral. Generar la primera versión con una subconsulta escalar correlacionada por id_cliente, y una alternativa con JOIN y GROUP BY/HAVING.

## Verificación requerida

Comparar con EXCEPT ALL en ambas direcciones y listas completas ordenadas sobre la base masiva y casos límite. Comprobar resultados esperados para empates, varios pedidos del mismo cliente, gasto 0, gasto exactamente 50.000, cliente sin pedidos, pedido entregado sin detalles, pedido cancelado y límite temporal superior excluido. Mantener ventas de productos/categorías dados de baja. Ejecutar fixtures y comprobaciones con ROLLBACK.
