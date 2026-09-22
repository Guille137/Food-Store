# Mapa de DML y consultas — objetivo 5

Los scripts ya desarrollados se conservan en sus carpetas; esta tabla permite identificar cada construcción sin duplicar versiones del SQL.

| Construcción | Consulta o script concreto | Resultado verificado |
|---|---|---|
| INSERT | [Registrar pedido](registrar_pedido.sql), [datos iniciales](../datos_iniciales.sql) | Cabecera y detalles; precio de venta tomado del catálogo; reversión integral ante error |
| UPDATE | [Baja lógica](baja_producto.sql), transiciones en [verificador](verificar_tpi.py) | Baja conserva fila/historia; PENDIENTE → CONFIRMADO → ENTREGADO |
| DELETE controlado | Pruebas de FK en [verificador](verificar_tpi.py) y de detalle en [TP2](../pruebas_restricciones.sql) | Producto vendido no puede eliminarse (23503); edición/borrado de detalle limitado a PENDIENTE |
| JOIN y agregación | [Facturación por categoría/mes](../tp4/a1_antes.sql) | SUM de cantidades/importes con cuatro tablas; catálogo vigente y pedidos entregados |
| GROUP BY / HAVING | [Alternativa al reporte correlacionado](../tp4/correlacionada_b.sql) | Clientes cuyo gasto entregado alcanza el umbral especificado |
| Subconsulta correlacionada | [Reporte correlacionado](../tp4/correlacionada_a.sql) | Mismo resultado que JOIN/HAVING, incluidos bordes |
| Función de ventana | [Ranking DENSE_RANK](../tp4/ranking_a.sql) | Empates conservan puesto; equivalencia contra alternativa sin ventana |
| Contraste de vistas | [Tres referencias independientes](../tp5/referencias_vistas.sql) | EXCEPT ALL bidireccional: cero diferencias |
| Función PL/pgSQL invocada desde SELECT | [tpi_total_pedido](funciones.sql) | Pedido con dos líneas: 45; vacío: 0; inexistente: P0002 |

La [equivalencia TP4](../tp4/informe_equivalencia.md) registra 5.000 filas normales para ambos reportes; con casos límite, 5.005 para ranking y 5.003 para el correlacionado. Se comprueban empates, umbral, ceros, pedidos cancelados y límites temporales.

Ejemplo de uso de los objetos nuevos, sobre una copia con el seed del proyecto:

```sql
BEGIN;
CALL tpi_registrar_pedido(
    1, 'EFECTIVO',
    '[{"id_producto":1,"cantidad":2},{"id_producto":3,"cantidad":1}]'::jsonb,
    NULL
);
-- CALL devuelve el id asignado. Usarlo en SELECT tpi_total_pedido(id).
-- Este ejemplo se revierte para no modificar la base de inspección.
ROLLBACK;
```

El ejecutor automatiza llamadas equivalentes, captura el id devuelto sin suponer valores de secuencias y comprueba el total con SQL. Las consultas de catálogo filtran vigencia; los reportes históricos conservan detalles y precio_unitario aunque el producto deje de venderse. La cancelación de pedido es un estado de negocio, no un DELETE ni una baja lógica de cliente.
