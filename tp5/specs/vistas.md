# Especificaciones previas — vistas

Generar tres vistas con nombres de columnas explícitos, sin SELECT *, sin alterar tablas. Preparar consultas de contraste sobre las tablas base, independientes de las vistas, y registrar la asistencia de Codex en la DUIA. Comparar multiconjuntos con EXCEPT ALL en ambos sentidos; comprobar además el mismo orden explícito en la consulta consumidora. Ensayar altas, bajas del catálogo y cancelaciones dentro de una transacción revertida.

## V1 — tp5_productos_vigentes

Columnas: `id_producto,nombre_producto,precio_lista,stock,id_categoria,nombre_categoria`.
JOIN producto/categoria; incluir solo producto.activo y categoria.activo. Consultar catálogo para reportes diarios. Ocultar columnas no enumeradas; no contiene datos de clientes. Orden externo por id_producto.
Aceptar si coincide exactamente con una consulta de referencia que primero obtiene categorías activas y luego sus productos activos, incluyendo casos de producto y categoría inactivos.

## V2 — tp5_pedidos_clientes

Columnas: `id_pedido,fecha,estado,forma_pago,id_cliente,nombre,apellido`.
JOIN pedido/cliente; conservar TODOS los estados: la tabla no tiene baja lógica y un cancelado también pertenece al historial. No inventar un filtro `eliminado` ni `cliente.activo`. Uso: historial operativo, actualizado al consultar; orden externo id_pedido.
Adaptación del ejemplo de seguridad: el esquema heredado llama cliente a la persona y NO contiene contraseña. Sin cambiarlo, proteger los datos existentes: excluir correo_electronico y nro_telefono. No afirmar que se probó ocultar una contraseña inexistente.
Aceptar si equivale a una referencia que proyecta primero los campos públicos del cliente. Crear rol NOLOGIN temporal de prueba, conceder USAGE del esquema y SELECT únicamente sobre la vista. Debe poder consultarla y recibir SQLSTATE 42501 al consultar cliente o pedido, y 42703 al pedir correo desde la vista. Revertir rol y GRANT. Mantener permisos normales del propietario sobre las tablas: no usar security_invoker=true, que exigiría permisos del consumidor sobre ellas. Esta vista no implementa aislamiento por cliente.

## V3 — tp5_detalles_productos

Columnas: `id_pedido,id_producto,nombre_producto,cantidad,precio_unitario,subtotal`.
JOIN detalle_pedido/producto; subtotal=cantidad*precio_unitario, conservar precisión NUMERIC. Es historia de ventas: NO filtrar por activo ni estado; conservar productos dados de baja y pedidos cancelados. Consumir con WHERE id_pedido para detalle individual; orden externo id_pedido,id_producto.
Aceptar si coincide con referencia que obtiene el nombre mediante subconsulta por PK, incluidas bajas posteriores, precio histórico distinto al actual y pedidos sin líneas (cero filas).
