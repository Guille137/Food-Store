# Evidencia de ejecución — TP2 Food Store

Ejecución actual: 22/09/2026, PostgreSQL 17.11 en Windows, psycopg 3.3.6. Instancia aislada local, usuario postgres, puerto 55432. Se utilizaron únicamente bases nuevas y datos sintéticos.

## Resultados comprobados

| Prueba | Resultado real |
|---|---|
| Restricciones | Pruebas válidas e inválidas aprobadas antes y después de instalar la migración; ensayos revertidos. |
| Traslado de detalles | Permitido entre pendientes; rechazado con origen o destino confirmado. |
| Edición y confirmación simultáneas | Espera observada en ambos órdenes; inserción rechazada después de la confirmación. |
| Lectura no repetible | READ COMMITTED: 10, 11. REPEATABLE READ: 10, 10. |
| Lectura fantasma | READ COMMITTED: 3, 4. REPEATABLE READ: 3, 3. |
| Bloqueo de fila | B esperó hasta COMMIT de A. NOWAIT devolvió 55P03. |
| Lectura crítica | UPDATE sin filtro: 3 filas; corregido: 1. NOT IN con NULL: 0; NOT EXISTS: 2. |

## Registro reproducible

- [Salida íntegra y comandos](evidencias/ejecucion_20260922_135107_303493.json), con `exito: true`.
- [Ejecutor](verificar_tp2.py), [pruebas de restricciones](pruebas_restricciones.sql) y [lectura crítica](pruebas_lectura_critica.sql).
- [Informe de concurrencia](informe_concurrencia.md), [DUIA Parte 1](duia_parte1.md) y [DUIA Partes 2 y 3](duia_partes2y3.md).

Los JSON registran consultas, respuestas del servidor, SQLSTATE y mensajes; no son resultados simulados. Las etiquetas de sesión permiten distinguir conexiones. En operaciones bloqueadas, el resultado se registra al finalizar la sentencia; el orden de lanzamiento está explícito en el ejecutor.

El primer ensayo de esta revisión se interrumpió por una tilde mal codificada en un mensaje esperado del verificador. Se conserva `evidencias/ejecucion_20260922_135041_693717.json` con `exito: false`. Tras corregirlo se ejecutó nuevamente todo el laboratorio con éxito.

Los resultados del 17/09 presentes en la versión anterior se conservan en el historial Git; la presente evidencia corresponde a una nueva ejecución reproducible y reemplaza el resumen incompleto anterior. No se afirma haber restaurado los dumps ni realizado la defensa oral.
