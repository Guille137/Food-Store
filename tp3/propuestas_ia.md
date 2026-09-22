# Propuestas sobre los planes reales, antes de aplicar cambios

Entrada: `evidencias/20260922_142245/q1_antes.txt`, `q2_antes.txt` y `q3_antes.txt`. Herramienta: Codex. Especificación: analizar esos planes, identificar el trabajo evitable y proponer índices o reescrituras equivalentes sin forzar el optimizador.

## Q1 — Productos por categoría y precio

El plan usa idx_producto_categoria y lee 16.668 referencias de índice. El Bitmap Heap Scan devuelve 1.672 filas y elimina 14.996 por el filtro de actividad/precio. Después un Sort top-N entrega las 50 primeras. Propuesta: índice parcial sobre (categoria_id, precio_lista, id_producto), con WHERE activo=TRUE e INCLUDE(nombre). La igualdad de categoría precede al rango de precio y al orden estable. Se espera eliminar el ordenamiento explícito y reducir lecturas; el índice puede cubrir la salida. No se garantiza Index Only Scan sin observar el plan y Heap Fetches.

## Q2 — Pedidos del día UTC

El plan usa Parallel Seq Scan, Sort y Gather Merge para devolver 549 filas. La condición convierte fecha a una fecha civil UTC fila por fila. Propuesta: reemplazarla por `fecha >= TIMESTAMPTZ '2025-06-15 00:00:00+00' AND fecha < TIMESTAMPTZ '2025-06-16 00:00:00+00'` y crear un índice por (fecha, id_pedido) que incluya estado y cliente_id. El rango respeta explícitamente UTC y el límite superior exclusivo. Se espera un acceso por rango y en el orden solicitado, evitando escanear toda la tabla.

## Q3 — Resumen de un producto vendido

El plan realiza Parallel Seq Scan sobre detalle_pedido y agrega el resultado. Filtra 199.996 filas por iteración con tres loops; devuelve 4 filas por iteración en promedio. La PK empieza por id_pedido y no sirve para localizar eficazmente id_producto aislado. Propuesta: índice sobre id_producto con INCLUDE(cantidad, precio_unitario). Se espera leer solo las líneas del producto para calcular count/sum. No se modifica la consulta ni el precio histórico guardado.

## Alternativas no aplicadas

- No duplicar idx_producto_categoria: ese índice ya aparece en el plan y no resuelve el filtro de precio ni el orden.
- No crear un índice solo sobre activo: es un booleano de baja selectividad y aquí interesa combinar categoría, rango y orden.
- No forzar `enable_seqscan=off`: ocultaría la decisión real del optimizador.
- No cambiar el filtro de Q2 a una fecha sin especificar zona horaria: podría cambiar los pedidos incluidos.

Estas alternativas se descartan por el análisis anterior, no por una medición que no se haya realizado. Los tres cambios candidatos se medirán y se informarán aunque alguno no mejore. Los índices consumen espacio y aumentan el mantenimiento de INSERT/UPDATE; su utilidad se limita a los accesos evaluados.

Fuentes: [EXPLAIN](https://www.postgresql.org/docs/17/using-explain.html), [índices multicolumna](https://www.postgresql.org/docs/17/indexes-multicolumn.html).
