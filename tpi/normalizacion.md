# Dependencias funcionales y normalización hasta BCNF

Se analiza el [modelo relacional](modelo.md) realmente implementado. Las dependencias se derivan de las reglas y restricciones, no de coincidencias en los datos de prueba. Escribir `X → Y` significa que un valor de X determina un único valor de Y en toda instancia válida de esa relación.

## Dependencias y claves candidatas

| Relación | Claves candidatas | Dependencias funcionales relevantes |
|---|---|---|
| categoria | {id_categoria}, {nombre} | id_categoria → nombre, activo; nombre → id_categoria, activo |
| cliente | {id_cliente}, {correo_electronico} | id_cliente → correo_electronico, nro_telefono, nombre, apellido; correo_electronico → id_cliente, nro_telefono, nombre, apellido |
| producto | {id_producto}, {nombre} | id_producto → nombre, precio_lista, stock, activo, categoria_id; nombre → id_producto, precio_lista, stock, activo, categoria_id |
| pedido | {id_pedido} | id_pedido → fecha, estado, forma_pago, cliente_id |
| detalle_pedido | {id_pedido, id_producto} | (id_pedido,id_producto) → precio_unitario, cantidad |

Los UNIQUE de nombre/correo son también NOT NULL: pueden utilizarse como claves candidatas. No se asume unicidad de nombre/apellido de cliente, teléfono ni del par cliente/fecha. No existe la dependencia estado → forma_pago ni categoria_id → precio_lista. Un mismo producto puede venderse con distinto precio en pedidos diferentes: **id_producto no determina precio_unitario en detalle_pedido**.

## Primera forma normal

Las tablas tienen atributos de valor único dentro de su dominio y una clave identificadora; no contienen listas de productos ni grupos repetidos. Varias líneas se representan como filas de DetallePedido. El JSONB del procedimiento de alta es un parámetro de intercambio: se valida y transforma en filas; no se almacena como una lista que sustituya el modelo relacional. El teléfono opcional es un único valor, no una lista de teléfonos.

## Segunda forma normal

En las cuatro entidades con claves candidatas simples no puede existir dependencia de un subconjunto propio no vacío de una clave. En DetallePedido, precio_unitario y cantidad dependen de la combinación completa:

- Un pedido contiene distintos productos y cantidades: id_pedido solo no los determina.
- Un producto aparece en distintos pedidos con cantidades y precios de venta distintos: id_producto solo no los determina.

Por eso no se guarda nombre ni precio de lista del producto en cada detalle. Esos atributos sí dependen solamente de id_producto y pertenecen a Producto.

## Tercera forma normal

No se guardan atributos descriptivos de otra entidad junto con su FK. Por ejemplo:

- En Pedido no se duplican nombre ni correo del cliente. En una tabla combinada existiría id_pedido → cliente_id → datos_cliente, una dependencia transitiva que provocaría anomalías de actualización.
- En Producto no se duplica nombre_categoria: pertenece a Categoría, determinado por categoria_id.
- En DetallePedido no se duplican fecha/estado del pedido ni nombre/stock del producto.

La descomposición separa cada determinante en su entidad y conserva FK para reconstruir los datos mediante JOIN. La vista puede proyectar atributos de varias tablas, pero no crea redundancia de almacenamiento en las tablas base. No se almacena un total de pedido que deba sincronizarse con cada cambio de cantidad/precio.

## Forma normal de Boyce–Codd

BCNF exige que todo determinante de una dependencia funcional no trivial sea una superclave. Bajo las dependencias del dominio indicadas arriba:

- En Categoria, Cliente y Producto los determinantes mínimos son las PK o sus claves alternativas UNIQUE NOT NULL.
- En Pedido el determinante mínimo es id_pedido.
- En DetallePedido el determinante mínimo es la pareja (id_pedido,id_producto).

Todos son claves candidatas; cualquier superconjunto también es superclave. Por tanto las cinco relaciones cumplen BCNF y, en consecuencia, 3FN. La conclusión depende de esas reglas: no se deducen dependencias adicionales por tener pocos ejemplos, por rangos de precios o por asociaciones circunstanciales de nombres.

## Reconstrucción y preservación de información

Las uniones DetallePedido–Pedido, DetallePedido–Producto, Pedido–Cliente y Producto–Categoria usan FK obligatorias que referencian una PK. Cada fila dependiente encuentra exactamente una fila padre, sin multiplicarse ni perderse en ese JOIN mientras se respeten las restricciones. Separar datos descriptivos evita su repetición y permite reconstruir los reportes. Las PK/UNIQUE implementan las dependencias enumeradas dentro de cada relación; las FK mantienen integridad referencial entre ellas.

La baja lógica no altera claves ni dependencias: conserva las filas y modifica activo. Las consultas deciden explícitamente entre catálogo vigente e historia. No se usan cascadas de borrado físico para implementar esa baja.
