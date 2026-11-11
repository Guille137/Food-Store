# Diseño — Plan de mantenimiento

## Componentes

| Archivo | Función | Rol de conexión |
|---|---|---|
| `tpi2/u6/00_instalar.sql` | Extensión `amcheck` | superusuario (una vez) |
| `respaldo.ps1` | `pg_dump -Fc`, verificación, SHA-256, roles, retención | `operador_respaldo` (solo lectura) |
| `restaurar.ps1` | Restauración cronometrada por fases, modos Prueba y Siniestro | superusuario de laboratorio |
| `prueba_restauracion.ps1` | Restaura el último respaldo en una base temporal y la elimina | superusuario de laboratorio |
| `mantenimiento.sql` / `mantenimiento.ps1` | VACUUM ANALYZE, REFRESH, métricas | superusuario de laboratorio |
| `verificar_integridad.sql` | amcheck, checksums, objetos inválidos, reglas de negocio | superusuario de laboratorio |
| `programar_tareas.ps1` | Registro en el Programador de tareas | cuenta de Windows del operador |

## Decisiones

- **Formato custom (`-Fc`).** Comprimido, permite restaurar selectivamente y listar el contenido para verificarlo.
- **`--create` en siniestro.** Recrea también los permisos a nivel base (`GRANT CONNECT`), que un `pg_restore` sobre una base creada a mano perdería. Por eso el modo siniestro se niega si la base existe: nunca pisa una base.
- **Roles aparte.** `pg_dump` no incluye roles (son del servidor). `pg_dumpall --roles-only --no-role-passwords` los guarda para reconstruir un servidor nuevo; las claves se vuelven a asignar.
- **Checksums de datos.** El servidor se inicializó con `--data-checksums`, lo que permite detectar páginas corruptas.
- **Sin contraseñas en scripts.** Archivo de contraseñas de PostgreSQL legible solo por la cuenta que ejecuta las tareas.

## Objetivos

| Métrica | Objetivo | Fundamento |
|---|---|---|
| RPO | ≤ 24 h | Respaldo diario |
| RTO | ≤ 15 min | Base de laboratorio pequeña; restauración + verificación automatizadas |

## Mejora identificada en el simulacro

El RPO de 24 h depende de que el respaldo diario funcione. Para bajarlo a minutos corresponde archivar WAL (`archive_mode = on`, `archive_command`) y habilitar recuperación a un instante (PITR) con un respaldo base (`pg_basebackup`). Se documenta como mejora en el informe post-incidente; no se implementa en el laboratorio.
