# Diseño — Colección `pedidos`

```text
pedidos {
  _id: int                      // id_pedido de PostgreSQL
  fecha: date
  estado: "PENDIENTE" | "CONFIRMADO" | "ENTREGADO" | "CANCELADO"
  forma_pago: "EFECTIVO" | "TARJETA" | "TRANSFERENCIA"
  cliente: { id_cliente: int, nombre: string, apellido: string }
  lineas: [ { id_producto: int, producto: string, categoria: string,
              cantidad: int, precio_unitario: decimal, subtotal: decimal } ]   // 1..n
  total: decimal                // = suma de subtotales (validado)
  cantidad_items: int           // = suma de cantidades (validado)
}
```

## Decisiones

- **Embeber las líneas.** Se leen siempre con su pedido y nunca fuera de él; su tamaño está acotado (1 a 4 líneas). Nombre de producto, categoría y precio son una foto de la venta: si mañana cambia el catálogo, el pedido histórico no debe cambiar.
- **Embeber un resumen del cliente, no referenciarlo.** Evita un `$lookup` en la consulta principal. El costo es la duplicación: un cambio de apellido toca todos los pedidos de ese cliente (medido en la evidencia). Correo y teléfono no viajan.
- **`_id` = `id_pedido`.** Trazabilidad directa con PostgreSQL y unicidad gratuita.
- **Decimal128.** `double` produce errores de redondeo en sumas de dinero.
- **Validador `$jsonSchema` + `$expr`.** Lo único que MongoDB puede garantizar al escribir. Las FK (cliente o producto existentes) no se pueden garantizar: las asegura el proceso de carga, que lee de PostgreSQL.
- **Índices.** `estado_fecha` (filtros por estado), `lineas_producto` (multiclave, búsqueda dentro del arreglo), `cliente_fecha` (historial).
- **Rol en la arquitectura.** MongoDB es una vista de lectura derivada; PostgreSQL sigue siendo la fuente de verdad. La colección se regenera desde PostgreSQL.

## Archivos

`tpi2/u7/01_exportar_pedidos.sql`, `02_crear_coleccion.js`, `03_cargar_pedidos.js`, `04_consultas.js`, `05_consultas.sql`, `06_pruebas_validador.js`, `comparacion_documental_relacional.md`.
