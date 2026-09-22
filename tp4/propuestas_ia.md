# Propuestas posteriores a la lectura de los planes iniciales

Entrada: planes A1 y A2 de `evidencias/20260922_151803`. IA: Codex. Se pide atacar los nodos observados, preservar la semántica y medir por separado el efecto de índices y reescritura.

## A1

El plan hace Parallel Seq Scan en pedido, un Nested Loop hacia detalle_pedido con 4.112 búsquedas por PK y otro Nested Loop hacia producto con 12.336 búsquedas. Finalmente ordena por categoría y hace Merge Join con categoria. Los 56.466 shared hits muestran trabajo repetido; la conversión mensual en el WHERE dificulta el acceso por fecha. Las estimaciones subestiman los pedidos de junio (148 filas estimadas frente a 2.056 de promedio por loop).

Propuesta: convertir el filtro al intervalo UTC [2025-06-01, 2025-07-01), agregar un índice parcial para pedidos ENTREGADO sobre (fecha,id_pedido) y un índice que cubra las columnas usadas de detalle_pedido por id_pedido. Se espera reducir el recorrido de pedidos y las visitas al heap al buscar sus líneas. El nuevo rango puede mejorar estimaciones y cambiar el algoritmo posterior; no se presupone que todos los joins deban ser Nested Loop ni que un algoritmo sea siempre superior.

## A2

El plan une detalle_pedido con pedido mediante Parallel Hash Join y luego une cliente con Hash Join. La entrada al agregado transporta nombre y apellido por cada línea, aunque el resultado final tiene 5.000 clientes. Propuesta: agrupar primero las líneas de pedidos entregados por cliente_id y unir cliente después. Se espera reducir las filas que llegan al join de nombres, la anchura transportada y el estado del agregado.

Los mismos índices candidatos de A1 se medirán con la consulta A2 original antes de reescribirla. Si un índice por sí solo no mejora, se registra. No se agrega un índice duplicado sobre cliente_id: el TP3 ya conserva idx_pedido_cliente. No se fuerza enable_hashjoin/enable_nestloop ni se atribuye una mejora a un algoritmo que el plan no haya utilizado.

## Criterio

Ensayar CREATE INDEX con ROLLBACK, aplicar en la copia después de respaldar y comparar cinco mediciones por etapa. Verificar EXCEPT ALL bidireccional y el orden completo. La competencia usa A2 y registra las tres etapas (original, índices sin reescritura y reescritura con índices), con el mismo volumen y condiciones. Se elige por tiempo real y se conservan los candidatos no elegidos.
