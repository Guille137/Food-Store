# Food Store — Base de Datos II

El **TP3** se encuentra en [tp3/README.md](tp3/README.md): carga masiva, optimizaciones medidas, lectura crítica y consultas equivalentes. La competencia de su Parte 5 queda pendiente del material oficial. El contenido siguiente corresponde al TP2.

Trabajo práctico 2: integridad, transacciones, concurrencia y lectura crítica de SQL. Resolución y evidencia ejecutada en PostgreSQL 17.11 sobre Windows.

## Entregables

| Parte | Archivos |
|---|---|
| Preparación | [Protocolo](protocolo_seguridad.md), [esquema del TP1](schema.sql), [datos iniciales](datos_iniciales.sql) |
| Integridad | [Especificación](spec_restricciones.md), [restricciones](restricciones_Food_Store.sql), [pruebas](pruebas_restricciones.sql), [DUIA](duia_parte1.md) |
| Concurrencia | [Informe con comandos, resultados y conclusiones](informe_concurrencia.md), [DUIA](duia_partes2y3.md) |
| Lectura crítica | [Resolución de los dos scripts](ejercicio_lectura_critica.md), [pruebas](pruebas_lectura_critica.sql), [DUIA](duia_partes2y3.md) |
| Evidencia | [Resumen de ejecución](evidencia_ejecucion_tp2.md) y registros en `evidencias/` |

Se utilizó Codex como herramienta de IA, conforme a la aclaración del alumno de que la elección de herramienta era libre. La declaración identifica el uso efectivo; no atribuye estas tareas a OpenCode ni Kiro.

## Reproducir las pruebas

Requisitos: Python 3.10 o posterior, un servidor PostgreSQL local para laboratorio, sus herramientas `pg_dump` y un usuario con permiso para crear bases. El ejecutor no instala el servidor. En la ejecución documentada se utilizó una instancia aislada en el puerto 55432.

Desde la raíz del repositorio, en PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe verificar_tp2.py --host 127.0.0.1 --port 55432 --user postgres --pg-bin 'C:\ruta\a\PostgreSQL\bin'
```

Reemplazar la ruta de binarios y el puerto por los de la instancia de laboratorio. Si el servidor requiere contraseña, usar la configuración habitual de libpq/pgpass; no guardar credenciales en el repositorio.

El ejecutor crea bases nuevas con fecha UTC, prepara la plantilla, respalda antes del DDL, ensaya con ROLLBACK y prueba las restricciones y las dos sesiones concurrentes. Termina con `OK: restricciones, concurrencia y lectura critica verificadas en PostgreSQL` y escribe un JSON en `evidencias/`. Si una comprobación falla, termina con error y guarda la ejecución como `exito: false`.

Las bases de laboratorio y los dumps se conservan para inspección; no hay eliminación automática. Cada ejecución usa nombres nuevos. Los dumps y dependencias locales están excluidos de Git.

## Alcance

- El control de stock compara cada línea con el stock actual; no reserva ni descuenta existencias.
- `schema.sql` recrea tablas: solo lo usa el ejecutor sobre una base nueva creada para el laboratorio.
- Las explicaciones de concurrencia se verificaron con tres escenarios; el interbloqueo opcional no se incluyó.
- La preparación de la defensa oral corresponde a cada integrante; las pruebas automatizadas no reemplazan su comprensión.
- Los commits de esta revisión describen cambios concretos. Se conserva el historial anterior sin reescribir commits compartidos.
