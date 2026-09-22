# DUIA - Partes 2 y 3

## Parte 2 - Concurrencia

| Campo | Registro |
|---|---|
| Herramienta | Codex (asistente de IA), modelo/proveedor según configuración de la sesión. |
| Spec o prompt utilizado | "Con el esquema Food Store, proponer pasos de dos sesiones para reproducir lectura no repetible, fantasma y espera por `FOR UPDATE`, y explicar qué aislamiento o mecanismo las evita." |
| Qué generó | El guion de comandos y explicaciones incluidos en `informe_concurrencia.md`. |
| Qué se aceptó | La secuencia de sesiones, los niveles `READ COMMITTED`/`REPEATABLE READ` y la prueba adicional con `NOWAIT`. |
| Qué se modificó o descartó, y por qué | Se excluyó el interbloqueo porque la consigna exige al menos tres escenarios y éste es opcional. Los ids se dejaron como datos de preparación para reemplazar por los de la copia real. |
| Verificación realizada | Pendiente de ejecutar en dos conexiones a PostgreSQL y de pegar la salida real por escenario. |

## Parte 3 - Lectura crítica

| Campo | Registro |
|---|---|
| Herramienta | Codex (asistente de IA), modelo/proveedor según configuración de la sesión. |
| Spec o prompt utilizado | "Analizar qué hacen realmente los dos scripts de la consigna y corregirlos, incluyendo el caso `NULL` de `NOT IN`." |
| Qué generó | `ejercicio_lectura_critica.md` con el análisis y las versiones corregidas. |
| Qué se aceptó | La explicación de ausencia de `WHERE` y el reemplazo de `NOT IN` por `NOT EXISTS`. |
| Qué se modificó o descartó, y por qué | El primer script usa `fecha_fin` como supuesto explícito, ya que el esquema genérico de `funcion` no fue suministrado. Debe ajustarse al nombre real de la columna antes de ejecutar. |
| Verificación realizada | La corrección se debe ensayar primero como `SELECT` y luego dentro de `BEGIN ... ROLLBACK` en el esquema correspondiente. |
