# Bitácora de uso de IA

Se utilizaron Codex para preparar, probar y revisar los scripts de TP8, y Kiro para revisar la especificación. OpenCode no terminó la revisión y no se le atribuye un resultado.

| Entrada | Qué se pidió | Qué se aceptó | Qué se descartó y por qué |
|---|---|---|---|
| 1 | Adaptar el esquema SQLite a las tablas mínimas y restricciones del enunciado. | Tablas `STRICT`, precios enteros en centavos y claves foráneas con `PRAGMA foreign_keys = ON`. | Guardar correos o credenciales; no hacen falta para el borrador y el TP prohíbe datos personales reales. |
| 2 | Diseñar un semáforo que clasifique solicitudes usando una instantánea del servidor. | Prioridad RECHAZADO sobre CONFLICTO y procesamiento solo de `PENDIENTE`. | Modificar precio, stock o pedidos en PostgreSQL desde SQLite; contradice la regla “el móvil propone, el servidor dispone”. |
| 3 | Adaptar la vista al modelo Food Store existente. | Usar `producto.activo`, `categoria.activo` y `precio_lista * 100`; mantener una fila de producto inactivo como lápida. | Reutilizar nombres genéricos de otra consigna (`usuario`, `eliminado` en PostgreSQL); el repositorio usa `cliente` y `activo`. |
| 4 | Revisar en Kiro los requisitos EARS, el diseño y las tareas. | Asignar C1 al requisito de catálogo offline y C7 al de restricciones; enumerar las cinco tablas SQLite y agregar `cargar_cache.sql` a la secuencia de tareas. | Incluir MongoDB dentro del alcance de los scripts móviles; queda documentado aparte como fuera de alcance de esta simulación. |
| 5 | Revisar los scripts de TP8 y comprobar casos dudosos sin cambiar el código. | Se identificó que una solicitud vacía puede aprobarse y que DBeaver debe normalizar booleanos a `t`/`f`; se descartó confundir categoría inactiva con producto eliminado. | Afirmar que OpenCode terminó o que se probaron cambios en la base PostgreSQL; OpenCode no respondió y las comprobaciones fueron en SQLite temporal. |

## Declaración de uso de IA

Codex se utilizó para analizar el enunciado y el repositorio, proponer scripts y documentación, y comprobar pruebas SQLite. Kiro se utilizó para revisar y corregir `requirements.md`, `design.md` y `tasks.md` según los casos C1 y C7 y las tablas y scripts presentes. Los escenarios PostgreSQL se ejecutaron en una copia de pruebas; la consulta final confirmó 5 pedidos y stock total 25. Se intentó usar OpenCode para la revisión, pero quedó sin responder; por eso no se declara realizada en esa herramienta.
