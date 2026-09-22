# Parte 3 — Ranking y subconsulta correlacionada

Las [especificaciones previas](spec_consultas.md) fijan período UTC, estados, política de bajas lógicas por tabla, columnas, partición, orden, empates y corte. La primera versión se generó a partir de esa spec; después se generó una alternativa distinta con IA, como permite la consigna. No se atribuye una versión a escritura humana independiente.

## Consultas

- [Ranking A](ranking_a.sql): suma por cliente y DENSE_RANK global por gasto descendente.
- [Ranking B](ranking_b.sql): suma por pedido y cliente, numeración de importes distintos con ROW_NUMBER y join con clientes. Así los clientes empatados reciben el mismo puesto y no hay saltos.
- [Correlacionada A](correlacionada_a.sql): subconsulta escalar que calcula el gasto entregado del cliente externo, comparado estrictamente con 50.000.
- [Correlacionada B](correlacionada_b.sql): JOIN, GROUP BY y HAVING con el mismo filtro y umbral.

## Verificación real

| Datos / consulta | Filas A | Filas B | A EXCEPT ALL B | B EXCEPT ALL A | Igual orden completo |
|---|---:|---:|---:|---:|---|
| ranking_masiva | 5000 | 5000 | 0 | 0 | Sí |
| correlacionada_masiva | 5000 | 5000 | 0 | 0 | Sí |
| ranking_bordes | 5005 | 5005 | 0 | 0 | Sí |
| correlacionada_bordes | 5003 | 5003 | 0 | 0 | Sí |

Se usó EXCEPT ALL para detectar también diferencias de multiplicidad; además se compararon las listas completas con su orden, no solo una muestra. Las muestras y consultas están registradas en [sesion.json](evidencias/20260922_151803/sesion.json).

## Casos límite comprobados

Se insertaron nueve clientes sintéticos y se probaron resultados esperados, además de la equivalencia:

| Caso | Resultado comprobado |
|---|---|
| Dos clientes empatados, uno con dos pedidos y otro con uno | Ambos suman 1.000.000 y tienen puesto 1 |
| Cliente con total 500.000 | Puesto 2, sin salto después del empate |
| Gasto 0 con línea entregada | Aparece en ranking, no supera el umbral |
| Total exactamente 50.000 | Aparece en ranking, no entra en el filtro > 50.000 |
| Sin pedidos | No aparece en ninguna consulta |
| Solo pedido CANCELADO | No aparece en ninguna consulta |
| Pedido ENTREGADO sin detalles | No aparece; no se inventa una línea ni un gasto |
| Pedido en 2026-01-01 00:00:00 UTC | Excluido por el límite superior abierto |
| Producto y categoría desactivados después de la venta | Las líneas entregadas de 2025 se conservan en ambos reportes históricos |

Los pedidos calificantes de prueba están exactamente en 2025-01-01 UTC: se comprueba también la inclusión del límite inferior. Se respetaron los triggers del TP2 para crear y transitar pedidos.

[casos_limite.sql](casos_limite.sql) prepara los datos y [verificar_bordes.sql](verificar_bordes.sql) comprueba importes, inclusión y puestos. La transacción terminó en ROLLBACK; el conteo posterior de clientes del fixture fue 0. Los errores esperados no se ocultaron: cualquier discrepancia de valor, orden, rango o puesto hace fallar el ejecutor.

La política de bajas lógicas es explícita: las tablas cliente, pedido y detalle_pedido no tienen activo/eliminado; para estos reportes históricos no se une ni filtra el catálogo. A1 de la Parte 1 tiene una política distinta, expresamente definida como catálogo vigente.

Referencia: [funciones de ventana en PostgreSQL](https://www.postgresql.org/docs/17/functions-window.html).
