# Requisitos — Tablet de feria con SQLite y sincronización (Unidad 8)

## Introducción

En las ferias, Food Store vende desde tablets que pueden quedarse sin conexión. La tablet guarda una copia del catálogo y los pedidos en SQLite; cuando hay red, propone esos pedidos al servidor PostgreSQL, que decide. Esta spec evoluciona `tp8/` e incorpora las correcciones de su revisión de código.

## Requisito 1 — Base local

1. La base SQLite DEBERÁ usar tablas `STRICT`, claves foráneas activas y restricciones `CHECK`.
2. La tablet NO DEBERÁ almacenar datos personales de clientes.
3. MIENTRAS no haya conexión, la persona DEBERÁ poder consultar el catálogo y armar borradores.
4. SI se recibe una instantánea vacía, ENTONCES la tablet DEBERÁ conservar el catálogo anterior.
5. Un borrador sin ítems NO DEBERÁ poder enviarse; un borrador enviado NO DEBERÁ poder modificarse; un borrador NO DEBERÁ tener dos solicitudes pendientes a la vez.

## Requisito 2 — Sincronización

1. CUANDO la tablet descargue el catálogo, DEBERÁ aplicarlo en una sola transacción y conservar como lápida lo que el servidor ya no publica.
2. CUANDO la tablet envíe una solicitud, el servidor DEBERÁ evaluarla con los datos actuales y responder `APLICADO`, `CONFLICTO` o `RECHAZADO` con los motivos.
3. SI una solicitud se reenvía con el mismo UUID, ENTONCES el servidor NO DEBERÁ crear un segundo pedido y DEBERÁ devolver la respuesta original.
4. SI no hay conexión, ENTONCES la solicitud DEBERÁ quedar `PENDIENTE` para reintentarse.
5. La tablet NO DEBERÁ poder escribir en ninguna tabla del servidor salvo a través de `sync.aplicar_solicitud`.

## Requisito 3 — Resolución de conflictos

1. SI un producto no existe, está dado de baja, su categoría está inactiva o no hay stock suficiente, ENTONCES la solicitud DEBERÁ ser `RECHAZADO` sin efectos en el servidor.
2. SI solo cambió el precio, ENTONCES la solicitud DEBERÁ ser `CONFLICTO`; la persona acepta el precio del servidor y se reenvía con un UUID nuevo.
3. CUANDO dos tablets pidan a la vez más unidades de las que hay, el servidor DEBERÁ aplicar una y rechazar la otra, sin dejar stock negativo.
4. CUANDO la solicitud se aplique, el servidor DEBERÁ crear el pedido `CONFIRMADO` con las reglas de `tpi_registrar_pedido` y descontar stock.
