# DUIA — Parte 1: restricciones de integridad

## Herramienta y alcance

Corrección actual: Codex de OpenAI, asistente basado en GPT-6 según la identificación de esta sesión. La interfaz no expone aquí un identificador de snapshot más específico. El modelo exacto de la generación anterior no quedó registrado; no se atribuye retrospectivamente.

El alumno aclaró que podía utilizarse la IA elegida. Se declara Codex como herramienta efectivamente utilizada; no se atribuye trabajo a OpenCode ni Kiro.

## Prompts y especificación

Prompt original conservado: "Sobre el esquema Food Store, crear reglas para: 1) permitir sólo PENDIENTE→CONFIRMADO/CANCELADO y CONFIRMADO→ENTREGADO/CANCELADO; 2) impedir editar detalles si el pedido no está PENDIENTE; 3) impedir detalles de producto inactivo o con cantidad mayor al stock."

Pedido de corrección: "Puedes modificar y arreglar todo eso en el repo? en cuanto al uso de la IA se podia usar la que prefirieramos"

Las reglas y el plan de pruebas se registraron en [spec_restricciones.md](spec_restricciones.md) antes de ejecutar la corrección en PostgreSQL.

## Qué generó y qué se aceptó

- Validación del pedido de origen y destino al trasladar un detalle.
- Bloqueos FOR SHARE en orden numérico, para impedir cambios concurrentes del estado durante la validación.
- Carga inicial sintética y pruebas válidas e inválidas con comprobaciones automáticas de SQLSTATE y mensaje.
- Pruebas adicionales con dos conexiones reales, en ambos órdenes de edición y confirmación.

## Qué se modificó o descartó y por qué

FOR KEY SHARE no bloqueaba el UPDATE de estado; se cambió por FOR SHARE. COALESCE solo seleccionaba el pedido nuevo al trasladar una línea; se reemplazó por una validación de ambos pedidos. Se separaron producto inactivo y stock insuficiente. Se conservó el alcance por línea del control de stock: no se implementó reserva ni descuento de existencias.

Durante el primer ensayo, un texto esperado tenía una tilde mal codificada. PostgreSQL devolvió el SQLSTATE correcto, pero la comparación del mensaje falló. Se corrigió la codificación y se repitió toda la ejecución. No se presenta ese primer ensayo como aprobado; se conserva el registro incompleto como antecedente técnico.

## Verificación realizada

PostgreSQL 17.11, copia de trabajo nueva. La migración y las pruebas se ensayaron con ROLLBACK. Después se confirmó solo la migración y se repitieron las pruebas con ROLLBACK; `SELECT count(*) FROM detalle_pedido` devolvió 0 al terminar.

Salidas NOTICE reales (sin repetir la segunda ejecución de las mismas pruebas):

```text
trigger "trg_validar_transicion_estado_pedido" for relation "pedido" does not exist, skipping
trigger "trg_validar_edicion_detalle_pedido" for relation "detalle_pedido" does not exist, skipping
trigger "trg_validar_producto_y_stock_detalle" for relation "detalle_pedido" does not exist, skipping
OK: Traslado entre pedidos pendientes
OK: Cantidad editable mientras el pedido esta pendiente
OK: PENDIENTE a CONFIRMADO
OK error esperado [23514]: Transición de estado no permitida: CONFIRMADO -> PENDIENTE
OK error esperado [23514]: No se puede editar el detalle del pedido 1 porque está CONFIRMADO
OK: Borrado permitido en pedido pendiente
OK error esperado [23514]: El producto 2 está inactivo
OK error esperado [23514]: Stock insuficiente para el producto 3: solicitado 6, disponible 5
OK: Cantidad igual al stock aceptada
OK error esperado [23514]: new row for relation "detalle_pedido" violates check constraint "chk_detalle_cantidad"
OK: CONFIRMADO a ENTREGADO
OK error esperado [23514]: Transición de estado no permitida: ENTREGADO -> CANCELADO
OK: CONFIRMADO a CANCELADO
OK error esperado [23514]: Transición de estado no permitida: CANCELADO -> PENDIENTE
OK error esperado [23514]: Transición de estado no permitida: PENDIENTE -> ENTREGADO
OK: PENDIENTE a CANCELADO
```

Las regresiones concurrentes también pasaron: el cambio de estado esperó hasta el ROLLBACK de la edición; en el orden inverso, la inserción esperó y luego recibió 23514 por pedido CONFIRMADO.

Archivos: [pruebas SQL](pruebas_restricciones.sql), [ejecutor](verificar_tp2.py), [registro íntegro](evidencias/ejecucion_20260922_135107_303493.json). La comprobación automatizada no reemplaza la comprensión ni la defensa oral del alumno.
