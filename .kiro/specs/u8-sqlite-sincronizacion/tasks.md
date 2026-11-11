# Tareas — Tablet de feria y sincronización

- [x] 1. Esquema SQLite STRICT con correcciones R1–R3 de la revisión de TP8 (`tpi2/u8/movil_schema.sql`) — _Req. 1_
- [x] 2. Lado servidor: vista de instantánea, tabla de solicitudes, función de aplicación (`servidor_sync.sql`) — _Req. 2.2, 2.3, 3_
- [x] 3. Permisos de `rol_sync_movil` en la matriz de la Unidad 5 (`tpi2/u5/04_roles.sql`) — _Req. 2.5_
- [x] 4. Cliente de la tablet: descarga, borradores, cola, envío, reintento, resolución de conflicto (`cliente_movil.py`) — _Req. 1.3, 1.4, 2.1, 2.4, 3.2_
- [x] 5. Casos probados (`ejecutar_todo.py`, paso `u8`)
  - [x] C0 instantánea sin datos personales
  - [x] C1 catálogo sin conexión
  - [x] C2 precio cambiado → conflicto → precio aceptado → aplicado
  - [x] C3 stock insuficiente → rechazado sin efectos
  - [x] C4 baja lógica → rechazado; lápida en la tablet
  - [x] C5 pedido sin cambios → aplicado, stock descontado
  - [x] C6 respuesta perdida → reenvío del mismo UUID → una sola venta
  - [x] C7 sin conexión → pendiente → reintento al reconectar
  - [x] C8 dos tablets por las últimas unidades → una aplicada, otra rechazada tras esperar el bloqueo
  - [x] C9 borrador vacío no se envía
  - [x] C10 instantánea vacía no reemplaza el catálogo
  - [x] C11 datos inválidos rechazados por SQLite
  - [x] Integridad local (`PRAGMA integrity_check`, `foreign_key_check`) y del servidor
