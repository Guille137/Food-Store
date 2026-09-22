# Reglas de integridad de Food Store

Esta especificación documenta las reglas del TP2 y guía la corrección del script existente.

1. **Estados de `pedido.estado`:** permitir PENDIENTE → CONFIRMADO/CANCELADO y CONFIRMADO → ENTREGADO/CANCELADO. Mantener el mismo estado es válido. No permitir salir de ENTREGADO ni CANCELADO. Se validan transiciones por UPDATE; el estado inicial continúa siendo el DEFAULT del esquema.
2. **Edición de `detalle_pedido`:** permitir INSERT, UPDATE y DELETE solo si el pedido está PENDIENTE. Al modificar `id_pedido`, comprobar origen y destino. Bloquear ambos pedidos en orden numérico hasta terminar la transacción, para que otra sesión no cambie su estado durante la validación.
3. **Producto y stock:** al insertar un detalle o cambiar `id_producto`/`cantidad`, exigir `producto.activo = TRUE` y `detalle_pedido.cantidad <= producto.stock`. Bloquear el producto mientras se comprueba. El CHECK original exige cantidad positiva.

La tercera regla compara cada línea con el stock disponible al validarla. No descuenta ni reserva stock, ni garantiza la suma de pedidos simultáneos: esas operaciones quedan fuera del alcance de esta regla y requieren una política propia.

## Plan de comprobación

- Preparar datos sintéticos identificables en una base nueva.
- Ensayar cada transición válida y rechazar retornos y salidas de estados finales.
- Probar inserción, actualización, borrado y traslado de detalles, con ambos pedidos pendientes y con origen o destino confirmado.
- Separar producto inactivo y stock insuficiente usando productos distintos.
- Probar dos sesiones cambiando el estado y editando detalles, en ambos órdenes.
- Ejecutar primero con ROLLBACK; aplicar la migración solamente después de observar los resultados.
