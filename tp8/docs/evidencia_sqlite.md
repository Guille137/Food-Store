# Evidencia de ejecución local

La revisión se ejecutó el 10/11/2026 en el motor SQLite 3.50.4 incluido en Python 3.13. No estaba disponible el programa de consola `sqlite3`; se ejecutó el SQL con la biblioteca SQLite, conservando transacciones y restricciones de claves foráneas.

## Resultado de `pruebas_sqlite.sql`

- COMMIT: quedó 1 borrador, 1 ítem y 1 solicitud.
- ROLLBACK: 0 filas nuevas.
- C1: consultó dos productos disponibles sin conexión.
- C7: cantidad cero falló por `CHECK (cantidad > 0)` y producto inexistente falló por FK; quedó el ítem válido original y ninguna fila inválida.

## Resultado de `pruebas_casos_sqlite.sql`

| Caso | Resultado observado en SQLite |
|---|---|
| C2 | Primera solicitud `CONFLICTO`; precio aceptado con UUID nuevo: `SIMULADO_APROBADO` |
| C3 | `RECHAZADO` por superar stock |
| C4 | `RECHAZADO`; lápida conservada y producto oculto del catálogo disponible |
| C5 | `SIMULADO_APROBADO` |
| C6 | UUID repetido produjo `UNIQUE constraint failed`; quedó una fila y no cambió al reejecutar |

Al final: `PRAGMA integrity_check` devolvió `ok` y `PRAGMA foreign_key_check` no devolvió filas. La prueba usa el CSV sintético de los datos iniciales y actualizaciones de snapshot simuladas localmente. No es evidencia de ejecución de los cambios ni de las exportaciones en PostgreSQL. Para esa evidencia, seguir `servidor/casos_postgresql.md` sobre una copia real.

## Estado de la base SQLite incluida

La solicitud C6 `80000000-0000-4000-8000-000000000206` quedó `SIMULADO_APROBADO`. Se intentó insertar otra vez el mismo UUID: SQLite devolvió `UNIQUE constraint failed: cola_sync.solicitud_uuid` y quedó una sola fila. Se comprobó que el borrador y el ítem asociados existen, `PRAGMA integrity_check` devuelve `ok` y `PRAGMA foreign_key_check` no informa filas.
