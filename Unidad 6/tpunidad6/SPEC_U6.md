# SPEC_U6 - Mantenimiento, respaldo y recuperación

**Grupo:** Victoria Guzman, Daniela Sosa, Octavio Skumanic, Sebastián Vivanco, Guillermo Sanchez

## Entorno y alcance

- Motor: PostgreSQL local.
- Base de origen en este entorno: `food_store_lab` (adaptación del nombre `foodstore` de la consigna).
- Base de restauración: `foodstore_restore_test`.
- La base de origen no se elimina ni se reemplaza.
- Los scripts no guardan contraseñas. La validación de productos usa la columna `precio_lista` del esquema existente.

## Tareas y criterios de éxito

| Tarea | Frecuencia propuesta | Evidencia de éxito |
|---|---|---|
| Respaldo custom con `pg_dump -Fc` | Diaria | Archivo `.dump` fechado, tamaño mayor que cero y log sin errores. |
| Chequeo de salud | Diario | Consultas ejecutadas y resultados guardados en un log o evidencia. |
| Revisión de mantenimiento | Semanal | Revisión de tuplas muertas, autovacuum y estadísticas; cualquier acción manual se justifica con esos datos. |
| Restauración de prueba | Semanal | Restauración en `foodstore_restore_test`; cantidades de filas coincidentes y validaciones lógicas sin errores. |

## Objetivos del simulacro

- RPO previsto: hasta 24 horas, suponiendo que el respaldo diario terminó correctamente.
- RTO objetivo de laboratorio: hasta 15 minutos para crear la base de prueba, restaurar y completar las validaciones.
- En el informe se registrarán el RPO y el RTO observados; estos valores no se inventan antes de ejecutar el simulacro.

## Seguridad

- Verificar la conexión y la base seleccionada antes de ejecutar cada procedimiento.
- No incluir contraseñas en scripts ni en el repositorio.
- Ejecutar la restauración únicamente en `foodstore_restore_test`.
- No usar `VACUUM FULL` como mantenimiento periódico.