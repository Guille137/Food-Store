# Parte 4 — Consultas equivalentes verificadas

Las [especificaciones](spec_consultas.md) se redactaron antes de generar las soluciones. Para cada consulta se creó una versión A y luego una alternativa B con distinta estructura, posibilidad admitida por la consigna. Ambas fueron generadas con asistencia de IA; no se atribuye una de ellas a escritura humana independiente.

| Consulta | Primera versión | Alternativa |
|---|---|---|
| Resumen de productos vigentes por categoría vigente | [LEFT JOIN y GROUP BY](parte4_resumen_a.sql) | [Preagregación y COALESCE](parte4_resumen_b.sql) |
| Productos activos sin líneas de pedidos no cancelados | [NOT EXISTS](parte4_subconsulta_a.sql) | [LEFT JOIN contra conjunto de vendidos](parte4_subconsulta_b.sql) |

## Resultados reales

| Datos | Consulta | Filas A | Filas B | A EXCEPT ALL B | B EXCEPT ALL A |
|---|---|---:|---:|---:|---:|
| Carga masiva | Resumen | 3 | 3 | 0 | 0 |
| Carga masiva | Subconsulta | 2 | 2 | 0 | 0 |
| Masiva + casos límite | Resumen | 6 | 6 | 0 | 0 |
| Masiva + casos límite | Subconsulta | 4 | 4 | 0 | 0 |

Además, se compararon las listas completas ordenadas A y B: coincidieron. EXCEPT ALL detecta también diferencias de multiplicidad; por sí mismo no comprueba el orden, de ahí la comparación adicional.

Los casos límite verifican categoría vacía, categoría solo con productos inactivos, categoría inactiva, producto sin venta, producto solo en pedido cancelado, producto en pedido vigente y producto de categoría inactiva. Se comprueban resultados esperados además de la coincidencia entre dos consultas, para evitar aceptar dos versiones igualmente equivocadas.

[verificar_equivalencia.sql](verificar_equivalencia.sql) contiene las vistas temporales, los casos y las comprobaciones. Todo se ejecutó dentro de una transacción terminada con ROLLBACK. La comparación y las muestras están en [sesion.json](evidencias/20260922_142245/sesion.json), campos equivalencia_parte4 y orden_parte4.

En el resumen, el filtro de producto activo está en el ON del LEFT JOIN para conservar categorías sin productos. COUNT(p.id_producto) devuelve cero para esas categorías; COUNT(*) devolvería uno y sería incorrecto. En la subconsulta, un producto con ventas solo canceladas sigue cumpliendo la condición; CANCELADO se excluye dentro del conjunto de ventas vigentes.
