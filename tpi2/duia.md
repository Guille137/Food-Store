# Declaración de Uso de IA (DUIA) — Segunda entrega

**Grupo:** Victoria Guzman, Daniela Sosa, Octavio Skumanic, Sebastián Vivanco, Guillermo Sanchez

## Herramientas

| Herramienta | ¿Se usó? | Para qué |
|---|---|---|
| **Claude Code** (Anthropic; modelos Claude Fable 5.2 y Claude Opus 5.5), extensión de VS Code | Sí | Analizar la consigna y el repositorio; redactar las specs; escribir y depurar SQL, PL/pgSQL, PowerShell, JavaScript (mongosh) y Python; ejecutar las pruebas en el servidor de laboratorio; auditoría de permisos; reconstrucción del incidente; code review; redacción de documentación |
| Kiro | **No** | Las specs están en `.kiro/specs/` con el formato de Kiro (requirements con criterios EARS, design, tasks), pero se redactaron con Claude Code, no generadas en Kiro |
| OpenCode | **No** | Los scripts no se generaron con OpenCode |
| Codex | En entregas anteriores | Declarado en sus DUIA ([TPI 1](../tpi/duia.md), [TP8](../tp8/docs/DUIA.md)); sus scripts se revisaron en el code review |

> La consigna pide specs en Kiro y scripts generados con OpenCode. Esta declaración no lo afirma porque no ocurrió. Ver "Pendiente del equipo".

## Prompt inicial y specs

Solicitud del alumno, junto con el texto completo de las condiciones de la segunda entrega y el enlace al repositorio:

> Este es el repositorio de github con el que tienes que hacer esto... Dame todo listo para entregar

Las specs que guiaron cada unidad están en [`.kiro/specs/`](../.kiro/specs/): `u4-migracion-legado`, `u5-roles-permisos`, `u6-mantenimiento`, `u7-modelo-documental`, `u8-sqlite-sincronizacion`. Los prompts específicos de la auditoría de seguridad, la reconstrucción del incidente, la consulta de equivalencia y el code review están transcriptos en sus documentos y resumidos en la [bitácora](bitacora_ia.md).

## Protocolo de uso sobre datos

- **Ningún script se ejecutó sin probarse** en una base nueva creada para la prueba o dentro de una transacción terminada en `ROLLBACK`; la migración tuvo además respaldo previo. `tpi2/ejecutar_todo.py` nunca reutiliza ni pisa una base existente.
- **Ningún dato personal real** se usó ni se envió al asistente: todos los datos son sintéticos y deterministas. Los logs se anonimizaron con `tpi2/u5/anonimizar_log.py` antes del análisis, y las evidencias se guardan sin rutas que identifiquen la cuenta del equipo.
- **Contraseñas:** ninguna en el repositorio. Las de los roles se generan al azar en cada corrida y viven solo en memoria; la del superusuario de laboratorio se lee de un archivo de contraseñas fuera del repositorio.

## Qué se aceptó y qué se descartó

Resumen; el detalle con su justificación está en la [bitácora](bitacora_ia.md), la [auditoría de permisos](u5/auditoria_permisos_ia.md), el [informe de incidente](u5/informe_incidente.md#5-contraste-con-lo-realmente-ejecutado), la [comparación documental](u7/comparacion_documental_relacional.md#contraste-con-lo-que-propuso-la-ia) y el [code review](code_review_final.md).

- **Aceptado tras probarlo:** esquema BCNF y migración con verificación de reunión sin pérdida; reversión en tres niveles; matriz de mínimo privilegio verificada contra el catálogo; `SECURITY DEFINER` acotado en lugar de `UPDATE` a la aplicación; auditoría de solo agregado; respaldo con rol de solo lectura y SHA-256; colección con `Decimal128` y validador; sincronización idempotente con `FOR UPDATE`.
- **Descartado:** `GRANT UPDATE` amplio a la aplicación; `tp5_pedidos_clientes` para reportes; devolver `TEMPORARY` a `PUBLIC`; importes `double` y correo embebido en MongoDB; bloquear una IP de documentación y forzar el cambio de clave de todos los administradores sin evidencia.
- **Errores de la IA detectados por las pruebas:** FK prematura en la migración, orden de borrado en la reversión, `TEMPORARY` revocado, rutas sin anonimizar, subconsulta en `CALL`, venta de feria sin descuento de stock, y una afirmación no sustentada en la reconstrucción del incidente.

## Pendiente del equipo antes de entregar

1. **Leer y poder explicar cada script.** La consigna lo exige para la defensa oral: un script que no se puede explicar equivale a no haberlo hecho.
2. **Kiro:** abrir el repositorio en Kiro (lee `.kiro/specs/` directamente), revisar las tres specs de cada unidad y registrar en la bitácora qué cambió Kiro, si cambió algo.
3. **OpenCode:** repetir en una sesión nueva al menos (a) la reconstrucción del incidente con solo el log anonimizado y (b) el code review, y agregar las respuestas a la bitácora. Si la cátedra exige que los scripts sean generados con OpenCode, consultar cómo acreditar lo hecho con otra herramienta (en la primera entrega se registró que el alumno confirmó libertad para elegir la herramienta).
4. **Firmar** las decisiones de la auditoría de permisos y del code review.
