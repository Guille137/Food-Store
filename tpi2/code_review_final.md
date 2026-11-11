# Code review final de los scripts de la cursada

## Alcance y método

Se revisaron con asistencia de IA (Claude Code, ver [DUIA](duia.md)) todos los scripts versionados del repositorio: `schema.sql`, `restricciones_Food_Store.sql`, `datos_iniciales.sql`, `pruebas_*.sql`, `tp3/`, `tp4/`, `tp5/`, `tpi/`, `tpUnidad4/`, `Unidad 6/tpunidad6/`, `unidad 7/` (ZIP), `tp8/` y los nuevos de `tpi2/`. Prompt utilizado:

> Revisá estos scripts SQL, PowerShell, JavaScript y Python como lo haría un revisor senior de bases de datos. Buscá errores de corrección, riesgos de seguridad, operaciones destructivas sin protección, supuestos no verificados, problemas de concurrencia y de portabilidad. Para cada hallazgo indicá archivo, línea o bloque, el escenario concreto en que falla y una corrección. No propongas cambios de estilo.

Cada hallazgo se comprobó ejecutando el caso (o leyendo el código cuando la ejecución no aplicaba) antes de decidir. La columna **Decisión** es la del equipo.

**Criterio para los trabajos anteriores:** sus scripts se conservan tal como se entregaron, porque son la evidencia de esas instancias. Cuando un hallazgo requería corregir, la corrección se hizo en `tpi2/` y se indica dónde.

## Hallazgos

| # | Archivo | Hallazgo | Escenario | Decisión |
|---|---|---|---|---|
| CR-01 | `schema.sql` | Empieza con `DROP TABLE … CASCADE` de las cinco tablas | Ejecutarlo por error sobre una base con datos la vacía | **Mantener** (es el DDL histórico). `tpi2/base/01_instalar_base.sql` lo envuelve: se niega a correr si `public` tiene tablas y ejecuta todo en una transacción |
| CR-02 | `restricciones_Food_Store.sql`, `tpi/registrar_pedido.sql`, `tpi/categorias_transicion.sql` | Los triggers y el procedimiento usan `FOR SHARE`, que exige privilegio `UPDATE` | Con mínimo privilegio, la aplicación no puede registrar pedidos salvo que se le dé `UPDATE` sobre producto y categoría | **Corregido en `tpi2/u5/04_roles.sql`:** las funciones pasan a `SECURITY DEFINER` con dueño `fs_owner` y `search_path` fijo (hallazgo H1) |
| CR-03 | `restricciones_Food_Store.sql` (R3) | El stock se valida por línea pero no se descuenta ni se reserva | Dos pedidos web concurrentes pueden vender la misma última unidad | **Aceptado como regla heredada** (documentada desde el TP2). Para la venta de feria, donde sí importa, `sync.aplicar_solicitud` bloquea con `FOR UPDATE` y descuenta (caso C8) |
| CR-04 | `tpUnidad4/tp_desnormalizacion_top_categorias.sql` | El trigger hace `REFRESH` completo de la materializada en **cada** sentencia de escritura sobre cuatro tablas | Escrituras más de 300 veces más lentas (0,64 → 209 ms medido en la U4); la migración de 817 renglones lo dispara varias veces | **Aceptado** con su salvaguarda (auditoría en 0 filas). Mejora propuesta: mantenimiento incremental por día afectado |
| CR-05 | `tpUnidad4/tp_desnormalizacion_top_categorias.sql` | `bloquear_ventas` rechaza cualquier escritura en aislamiento distinto de `READ COMMITTED` | Una aplicación que use `REPEATABLE READ` no puede vender | **Aceptado y documentado.** `sync.aplicar_solicitud` y la migración corren en `READ COMMITTED` |
| CR-06 | `tpUnidad4/tp_fnbc_control_lote.sql` | `CREATE SCHEMA unidad4` sin `IF NOT EXISTS`: no es re-ejecutable | Segunda ejecución falla | **Correcto así:** fallar es preferible a reinstalar sobre datos existentes (documentado en su README) |
| CR-07 | `Unidad 6/tpunidad6/backup_foodstore.ps1` | Usa `--password` (pide la clave por teclado) | No puede correr desatendido desde el Programador de tareas | **Corregido en `tpi2/u6/respaldo.ps1`** (`--no-password` + archivo de contraseñas) |
| CR-08 | `Unidad 6/tpunidad6/backup_foodstore.ps1` | Conecta como `postgres` (superusuario) | Una credencial de respaldo filtrada da control total | **Corregido:** `operador_respaldo`, solo lectura |
| CR-09 | `Unidad 6/tpunidad6/backup_foodstore.ps1` | `2>&1 \| Tee-Object` con `$ErrorActionPreference = "Stop"` en PowerShell 5.1 | Cualquier aviso de `pg_dump` por stderr aborta el script como error | **Corregido:** stderr se redirige a archivo con `Start-Process` |
| CR-10 | `Unidad 6/tpunidad6/backup_foodstore.ps1` | No verifica que el respaldo sea restaurable; ruta de PostgreSQL 18 fija; el log queda con `TamaÃ±o` (codificación) | El respaldo puede estar truncado sin que nadie lo note | **Corregido:** `pg_restore --list`, SHA-256, `-PgBin` parametrizado |
| CR-11 | `Unidad 6/tpunidad6/maintenance.sql` | Solo `ANALYZE`; sin `VACUUM`, sin verificación de integridad | — | **Corregido** en `tpi2/u6/mantenimiento.sql` y `verificar_integridad.sql` |
| CR-12 | `Unidad 6/tpunidad6/backups/*.dump` | Respaldos versionados en Git, contra la regla de `AGENTS.md` | Un respaldo con datos reales quedaría público | **Se conservan** (datos sintéticos, evidencia de la U6). `.gitignore` ahora excluye los respaldos y registros de `tpi2/` |
| CR-13 | `unidad 7/consultas_mongodb.js` | Importes como `double`; `total` sin validar; correo del cliente embebido | Sumas con error de redondeo; totales inconsistentes aceptados | **Corregido** en `tpi2/u7/` (`Decimal128`, validador `$expr`, sin correo) |
| CR-14 | `unidad 7/consultas_postgresql.sql` | Inserta pedidos 4 y 5 en la base sobre la que se ejecuta | Ejecutarlo en otra base agrega pedidos de prueba | **Aceptado** (era el escenario de 5 pedidos de la consigna). `tpi2/u7` solo lee |
| CR-15 | `tp8/servidor/snapshot_postgresql.sql` | La vista no tiene la columna `stock`, pero la tabla SQLite `snapshot_servidor` la exige | El `\copy` exportado no se puede importar tal cual | **Corregido** en `tpi2/u8/servidor_sync.sql` |
| CR-16 | `tp8/movil/semaforo.sql` | Una solicitud sin ítems queda `SIMULADO_APROBADO` | Pedido vacío "aprobado" | **Corregido** (trigger local + validación en servidor, caso C9) |
| CR-17 | `tp8/movil/schema_sqlite.sql` | Un borrador admite varias solicitudes `PENDIENTE` | Resultados duplicados | **Corregido** (índice único parcial) |
| CR-18 | `tp8/movil/cargar_cache.sql` | Con `snapshot_servidor` vacío marca todo el catálogo como baja | La tablet queda sin catálogo | **Corregido** (`CHECK (productos > 0)`, caso C10) |
| CR-19 | `tp8/movil/pruebas_sqlite.sql`, `pruebas_casos_sqlite.sql` | Empiezan con `DELETE FROM` de todas las tablas | Ejecutarlas sobre la base de una tablet real borra sus borradores | **Aceptado** para TP8 (base de prueba). En `tpi2/u8` cada prueba crea su propia base |
| CR-20 | `tpi2/u5/04_roles.sql` (versión inicial) | Otorgaba a `rol_reportes` la vista `tp5_pedidos_clientes`, con nombre y apellido de clientes | Un analista ve datos personales | **Corregido** (H3) |
| CR-21 | `tpi2/u5/04_roles.sql` (versión inicial) | Al revocar todo a PUBLIC se quitó `TEMPORARY` y `REFRESH … CONCURRENTLY` falló | El mantenimiento semanal falla | **Corregido** (H9): `TEMPORARY` solo para `fs_owner` |
| CR-22 | `tpi2/u5/01_usuario_autenticacion.sql` (versión inicial) | Respuesta más rápida para cuentas inactivas o bloqueadas | Enumeración de cuentas por tiempo | **Corregido** (H5) |
| CR-23 | `tpi2/u4/05_reversion.sql` (versión inicial) | Borraba pedidos antes de eliminar los mapas que los referencian | La reversión fallaba por FK y no revertía nada | **Corregido**; detectado por la prueba de reversión |
| CR-24 | `tpi2/u8/servidor_sync.sql` (versión inicial) | No descontaba stock en la venta de feria | Dos tablets venden la misma última unidad | **Corregido** (`FOR UPDATE` + descuento, caso C8) |
| CR-25 | `tpi2/u8/servidor_sync.sql` (versión inicial) | Subconsulta como argumento de `CALL` | Error en tiempo de ejecución en cada pedido aplicado | **Corregido**; detectado por la prueba C5 |
| CR-26 | `tpi2/u5/anonimizar_log.py` (versión inicial) | No enmascaraba rutas locales, que contienen el usuario de Windows | El "log anonimizado" seguía identificando a una persona | **Corregido** (`[RUTA]`); `restos()` también lo controla |
| CR-27 | `tpi2/u5/02_auditoria.sql` | `auditoria.registro` guarda correo y teléfono antes/después | La auditoría es otra copia de datos personales | **Aceptado** (H7): es lo que permite revertir; acceso solo `rol_auditor` |
| CR-28 | `tpi2/u6/restaurar.ps1` | El nombre de base de modo Prueba se interpola en SQL | Inyección vía `-BaseDestino` | **Mitigado:** se valida contra `^[a-z_][a-z0-9_]*$` antes de usarlo |

## Resumen

28 hallazgos: 18 corregidos (11 de scripts de unidades anteriores, corregidos en `tpi2/`, y 7 de scripts nuevos, corregidos antes de entregar), 8 aceptados o mitigados con justificación, 2 mantenidos por diseño. Ningún hallazgo quedó sin decisión.

## Firma del equipo

- [ ] Victoria Guzman
- [ ] Daniela Sosa
- [ ] Octavio Skumanic
- [ ] Sebastián Vivanco
- [ ] Guillermo Sanchez
