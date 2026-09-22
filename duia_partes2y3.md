# DUIA — Partes 2 y 3

## Herramienta

Se utilizó Codex de OpenAI. Para la corrección actual, la sesión identifica al asistente como basado en GPT-6; no expone un snapshot más específico. El modelo exacto de la generación anterior no quedó registrado. El alumno aclaró que la elección de herramienta era libre.

Pedido actual: "Puedes modificar y arreglar todo eso en el repo? en cuanto al uso de la IA se podia usar la que prefirieramos"

## Parte 2 — Concurrencia

| Campo | Registro |
|---|---|
| Prompt original conservado | "Con el esquema Food Store, proponer pasos de dos sesiones para reproducir lectura no repetible, fantasma y espera por `FOR UPDATE`, y explicar qué aislamiento o mecanismo las evita." |
| Qué generó | Comandos y explicaciones del informe; en esta revisión, ejecutor con dos conexiones reales y captura de salidas. |
| Qué se aceptó | Las explicaciones originales, los niveles READ COMMITTED/REPEATABLE READ y la prueba NOWAIT. |
| Qué se modificó o descartó | Se reemplazaron ids supuestos por una carga conocida, se agregó BEGIN explícito en B para el fantasma y se completó su repetición en REPEATABLE READ. El interbloqueo opcional no se incluyó. |
| Verificación realizada | Stock 10→11 en READ COMMITTED y 10→10 en REPEATABLE READ. Conteo 3→4 y 3→3 respectivamente. Espera confirmada en pg_stat_activity y error 55P03 con NOWAIT. |
| Conclusión | Las tres explicaciones quedaron confirmadas en PostgreSQL 17.11. |

Las explicaciones de IA se conservan literalmente en [informe_concurrencia.md](informe_concurrencia.md), junto con comandos y resultados.

## Parte 3 — Lectura crítica

| Campo | Registro |
|---|---|
| Prompt original conservado | "Analizar qué hacen realmente los dos scripts de la consigna y corregirlos, incluyendo el caso `NULL` de `NOT IN`." |
| Qué generó | Análisis, scripts corregidos y pruebas con tablas temporales del esquema genérico. |
| Qué se aceptó | La necesidad de WHERE y la corrección con NOT EXISTS. |
| Qué se modificó o descartó | Se precisó que NOT IN con NULL devuelve FALSE para coincidencias y UNKNOWN para no coincidencias. Se conservó id en el ejemplo genérico y se separó la adaptación a id_categoria y baja lógica de Food Store. |
| Supuesto explícito | fecha_fin representa la finalización de cartel; el esquema de funcion no fue suministrado y no pertenece a Food Store. |
| Verificación realizada | UPDATE original: 3 filas. Corregido: 1 fila, manteniendo la función vigente. NOT IN con NULL: 0 filas; NOT EXISTS: 2 categorías no referenciadas. Todo dentro de ROLLBACK. |

La adaptación de baja lógica de Food Store es una propuesta documentada; los ensayos de esta parte se realizaron sobre el esquema genérico temporal. [Registro completo](evidencias/ejecucion_20260922_135107_303493.json).
