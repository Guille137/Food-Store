# Diseño — Food Store sin conexión

PostgreSQL mantiene la verdad del catálogo. `v_snapshot_movil` entrega una copia acotada del catálogo, incluidos productos inactivos como lápidas, sin clientes ni datos personales. SQLite almacena cinco tablas STRICT: `producto_cache` (catálogo local navegable offline), `pedido_borrador`, `item_borrador`, `cola_sync` (cola con `solicitud_uuid` como PK) y `snapshot_servidor` (tabla de importación del CSV exportado desde PostgreSQL, con booleanos guardados como texto `t`/`f`). El semáforo solo lee `snapshot_servidor` y actualiza el resultado en `cola_sync`: no escribe en PostgreSQL ni confirma ventas.

El precio viaja como centavos enteros. La sincronización se considera idempotente en la tablet porque `semaforo.sql` solo procesa filas con `estado = 'PENDIENTE'` y `solicitud_uuid` es clave primaria. Una solución real también debe aplicar la idempotencia al recibir la solicitud en el servidor; ese receptor no forma parte de esta simulación.

**Fuera del alcance de esta simulación:** MongoDB mantiene en el sistema completo una colección `pedidos` desnormalizada con cliente y líneas con precios históricos; PostgreSQL conserva la autoridad sobre los datos transaccionales. SQLite no recibe datos de clientes. Ninguno de esos componentes forma parte de los scripts entregados en este TP.
