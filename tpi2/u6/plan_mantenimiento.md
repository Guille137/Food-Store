# Unidad 6 — Plan de mantenimiento

Spec: [requirements](../../.kiro/specs/u6-mantenimiento/requirements.md) · [design](../../.kiro/specs/u6-mantenimiento/design.md) · [tasks](../../.kiro/specs/u6-mantenimiento/tasks.md). Evidencia: archivos `u6_*` de [`evidencias/20261110_204915/`](../evidencias/20261110_204915/).

## Calendario

| Tarea | Frecuencia | Script | Rol | Criterio de éxito |
|---|---|---|---|---|
| Respaldo completo `pg_dump -Fc` + SHA-256 + roles | Diario 02:00 | [`respaldo.ps1`](respaldo.ps1) | `operador_respaldo` (solo lectura) | Código 0, tamaño > 0, índice legible, `.sha256` escrito |
| Limpieza y estadísticas (`VACUUM (ANALYZE)`), refresco de materializadas y copias anónimas, métricas | Domingo 03:00 | [`mantenimiento.ps1`](mantenimiento.ps1) → [`mantenimiento.sql`](mantenimiento.sql) | superusuario de laboratorio | Sin errores |
| Verificación de integridad | Domingo 03:00 (tras el anterior) y después de **cada** restauración | [`verificar_integridad.sql`](verificar_integridad.sql) | superusuario de laboratorio | `INTEGRIDAD VERIFICADA` |
| Restauración de prueba del último respaldo | Domingo 04:00 | [`prueba_restauracion.ps1`](prueba_restauracion.ps1) → [`restaurar.ps1`](restaurar.ps1) | superusuario de laboratorio | Integridad verificada y base temporal eliminada |
| Retención | Con cada respaldo | `respaldo.ps1` | — | Se borran los de más de 14 días de esa base |

Registro en Windows: [`programar_tareas.ps1`](programar_tareas.ps1). Sin `-Registrar` solo muestra lo que haría ([salida](../evidencias/20261110_204915/u6_04_programacion.txt)); con `-Registrar` crea las tres tareas con `StartWhenAvailable` (si el equipo estaba apagado, corre al encender) y un límite de una hora.

```powershell
.\tpi2\u6\programar_tareas.ps1 -Base food_store -PgBin "C:\Program Files\PostgreSQL\17\bin" -Puerto 5432 -PgPassFile C:\seguro\pgpass.conf -Registrar
```

## Qué verifica la integridad

| Control | Cómo |
|---|---|
| Estructura de índices B-tree y que cada fila esté indexada | `bt_index_check(indice, true)` de amcheck sobre todos los índices del proyecto |
| Páginas corruptas | Checksums de datos activos y `checksum_failures = 0` |
| Objetos inválidos | Índices inválidos, restricciones sin validar, **triggers deshabilitados** (la migración de la U4 los suspende), materializadas sin datos |
| Reglas de negocio no declarativas | Pedidos confirmados sin líneas, desnormalización U4 desincronizada, claves sin hash bcrypt, solicitudes de sincronización colgadas |
| Copia anónima vieja | Aviso (no error): se corrige con el refresco semanal |
| Conteos e importe total | Para comparar contra el origen tras restaurar |

## Pruebas realizadas

| Prueba | Resultado |
|---|---|
| Mantenimiento completo | Correcto; integridad verificada ([log](../evidencias/20261110_204915/u6_01_mantenimiento.txt)) |
| Respaldo diario | 220.543 bytes, 336 objetos, 3,34 s ([log](../evidencias/20261110_204915/u6_02_respaldo.txt)) |
| Respaldo con un rol inexistente | Código 1, **ningún** `.dump` en la carpeta |
| Restauración de prueba del último respaldo | Integridad verificada; base temporal eliminada ([salida](../evidencias/20261110_204915/u6_03_prueba_restauracion.txt)) |
| Respaldo con un byte alterado | Rechazado antes de restaurar: SHA-256 distinto |
| Simulacro de desastre | RTO 7,94 s; ver [informe post-incidente](informe_post_incidente.md) |

## Diferencias con la entrega anterior de la Unidad 6

[`Unidad 6/tpunidad6/`](../../Unidad%206/tpunidad6/) se conserva sin cambios. Este plan corrige lo encontrado en su revisión (ver [code review](../code_review_final.md)): el respaldo pedía la contraseña (`--password`) y no podía correr desatendido; usaba el superusuario; tenía la ruta de PostgreSQL 18 fija; no verificaba que el archivo fuera restaurable; el mantenimiento solo hacía `ANALYZE`; no había verificación de integridad ni programación.
