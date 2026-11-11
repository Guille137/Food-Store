# Segunda entrega del TPI — Food Store (Unidades 4 a 8)

**Grupo:** Victoria Guzman, Daniela Sosa, Octavio Skumanic, Sebastián Vivanco, Guillermo Sanchez

Capa de datos completa del proyecto: relacional (PostgreSQL 17.11), documental (MongoDB 8.0.15) y móvil (SQLite 3.43), con specs, scripts versionados, plan de mantenimiento y bitácora de IA.

**Empezar por:** [Informe técnico](informe_tecnico.md) → esta tabla → [evidencias de la corrida](evidencias/20261110_204915/) (`resultado.json`: 132/132 comprobaciones).

## Los 15 objetivos y dónde está cada uno

| # | Objetivo | Implementación | Evidencia |
|---|---|---|---|
| **U4.1** | Esquema heredado refactorizado hasta BCNF, validado contra las DF reales | [01_esquema_heredado.sql](u4/01_esquema_heredado.sql), [02_verificar_dependencias.sql](u4/02_verificar_dependencias.sql), [normalizacion_bcnf.md](u4/normalizacion_bcnf.md) | [u4_01](evidencias/20261110_204915/u4_01_dependencias_funcionales.txt), [u4_06](evidencias/20261110_204915/u4_06_resultado_modelo.txt) |
| **U4.2** | Migración sin pérdida en transacciones reversibles, especificada en Kiro, con plan de reversión | [spec](../.kiro/specs/u4-migracion-legado/), [03_migracion.sql](u4/03_migracion.sql), [04_verificar_migracion.sql](u4/04_verificar_migracion.sql), [05_reversion.sql](u4/05_reversion.sql) | [u4_02 ensayo](evidencias/20261110_204915/u4_02_ensayo_con_rollback.txt), [u4_03 reversión](evidencias/20261110_204915/u4_03_reversion.txt), [u4_05 huellas](evidencias/20261110_204915/u4_05_huellas.txt) |
| **U4.3** | Desnormalización controlada documentada | [normalizacion_bcnf.md §6](u4/normalizacion_bcnf.md#6-desnormalización-controlada) | Auditoría U4 = 0 filas en [u4_06](evidencias/20261110_204915/u4_06_resultado_modelo.txt) |
| **U5.1** | Usuarios, roles y permisos con mínimo privilegio | [spec](../.kiro/specs/u5-roles-permisos/), [01](u5/01_usuario_autenticacion.sql), [04_roles.sql](u5/04_roles.sql), [06_verificar_permisos.sql](u5/06_verificar_permisos.sql) | [u5_03](evidencias/20261110_204915/u5_03_verificacion_permisos.txt), [u5_04](evidencias/20261110_204915/u5_04_pruebas_por_rol.txt), [u5_05](evidencias/20261110_204915/u5_05_privilegios_por_defecto.txt) |
| **U5.2** | Auditoría activada y probada con simulacro, reconstruida desde el log, con contención | [02_auditoria.sql](u5/02_auditoria.sql), [05_config_auditoria.sql](u5/05_config_auditoria.sql), [simulacro_incidente.py](u5/simulacro_incidente.py), [09_contencion.sql](u5/09_contencion.sql), [informe_auditoria.md](u5/informe_auditoria.md), [informe_incidente.md](u5/informe_incidente.md) | [u5_07](evidencias/20261110_204915/u5_07_log_auditoria_prueba.txt), [u5_08 log anonimizado](evidencias/20261110_204915/u5_08_log_simulacro_anonimizado.txt), [u5_09](evidencias/20261110_204915/u5_09_simulacro_pasos.txt), [u5_10](evidencias/20261110_204915/u5_10_contencion.txt) |
| **U5.3** | Auditoría de seguridad del esquema asistida por IA con decisión humana | [08_auditoria_seguridad.sql](u5/08_auditoria_seguridad.sql), [auditoria_permisos_ia.md](u5/auditoria_permisos_ia.md) | [u5_06](evidencias/20261110_204915/u5_06_auditoria_seguridad.txt) |
| **U6.1** | Plan de mantenimiento: respaldo programado, restauración probada, tareas rutinarias, automatizado y documentado | [spec](../.kiro/specs/u6-mantenimiento/), [plan_mantenimiento.md](u6/plan_mantenimiento.md), [respaldo.ps1](u6/respaldo.ps1), [restaurar.ps1](u6/restaurar.ps1), [prueba_restauracion.ps1](u6/prueba_restauracion.ps1), [mantenimiento.sql](u6/mantenimiento.sql), [verificar_integridad.sql](u6/verificar_integridad.sql), [programar_tareas.ps1](u6/programar_tareas.ps1) | [u6_01](evidencias/20261110_204915/u6_01_mantenimiento.txt) a [u6_04](evidencias/20261110_204915/u6_04_programacion.txt) |
| **U6.2** | Simulacro de desastre contra reloj con informe post-incidente | [informe_post_incidente.md](u6/informe_post_incidente.md) | [u6_05](evidencias/20261110_204915/u6_05_simulacro_desastre.txt) — RTO 7,94 s |
| **U7.1** | Parte del dominio en base documental, consultas verificadas sobre datos reales | [spec](../.kiro/specs/u7-modelo-documental/), [01](u7/01_exportar_pedidos.sql) a [06](u7/06_pruebas_validador.js) | [u7_01](evidencias/20261110_204915/u7_01_carga.txt), [u7_03](evidencias/20261110_204915/u7_03_resultados_mongodb.json), [u7_05](evidencias/20261110_204915/u7_05_validador_y_duplicacion.json) |
| **U7.2** | Comparación documentada documental vs. relacional y justificación | [comparacion_documental_relacional.md](u7/comparacion_documental_relacional.md) | [u7_02](evidencias/20261110_204915/u7_02_comparacion_consultas.txt) |
| **U8.1** | Base SQLite con esquema y sincronización especificados | [spec](../.kiro/specs/u8-sqlite-sincronizacion/), [movil_schema.sql](u8/movil_schema.sql), [cliente_movil.py](u8/cliente_movil.py), [servidor_sync.sql](u8/servidor_sync.sql) | [u8_tablets/](evidencias/20261110_204915/u8_tablets/) |
| **U8.2** | Sincronización simulada con conflictos probados y resueltos | [sincronizacion.md](u8/sincronizacion.md) | [u8_01](evidencias/20261110_204915/u8_01_casos_sincronizacion.txt), [u8_03](evidencias/20261110_204915/u8_03_estado_servidor.txt) |
| **U8.3** | Code review final asistido por IA con decisión humana sobre cada hallazgo | [code_review_final.md](code_review_final.md) | 28 hallazgos, todos con decisión |
| **U8.4** | Capa de datos completa con specs, Git, plan de mantenimiento y bitácora | Este directorio, [.kiro/specs/](../.kiro/specs/), [bitacora_ia.md](bitacora_ia.md), [duia.md](duia.md) | Rama `segunda-entrega`, un commit por unidad |

## Reproducir

Requisitos: PostgreSQL 16+ (probado en 17.11) con un superusuario de laboratorio, MongoDB + `mongosh`, Python 3.10+ (solo biblioteca estándar) y PowerShell 5.1+. El servidor de PostgreSQL debe tener `logging_collector = on` (las pruebas de auditoría leen el log) y, para el control de checksums, haberse creado con `initdb --data-checksums`.

```powershell
$env:PGPASSFILE = "C:\ruta\segura\pgpass.conf"    # clave del superusuario, fuera del repositorio
python tpi2/ejecutar_todo.py --pg-bin "C:\Program Files\PostgreSQL\17\bin" --port 5432 `
    --mongosh mongosh --mongo-uri mongodb://127.0.0.1:27017
```

El ejecutor crea `food_store_tpi2_<fecha_hora>` (nunca pisa una base existente), una base MongoDB del mismo nombre y dos bases SQLite, ejecuta los pasos `base,u4,u5,u6,u7,u8` y deja todo en `tpi2/evidencias/<fecha_hora>/`. Las contraseñas de los roles se generan al azar en cada corrida. **Modifica la configuración de auditoría del servidor** (`ALTER SYSTEM`) y crea roles a nivel servidor: usar un servidor de laboratorio, no uno compartido.

Para instalar sobre una base propia sin el ejecutor, el orden es: `base/01_instalar_base.sql` → `u4/01` → `u4/03`+`u4/04` en una transacción → `u5/01`, `02`, `03` → `u8/servidor_sync.sql` → `u5/04_roles.sql` (con las variables `clave_*`) → `u5/05_config_auditoria.sql` → `u6/00_instalar.sql`.

## Estructura

```text
tpi2/
├── base/        instalación de las unidades 1-3 y datos sintéticos; huella de contenido
├── u4/          esquema heredado, dependencias, migración, verificación, reversión
├── u5/          usuarios, auditoría, anonimización, roles, simulacro, contención
├── u6/          respaldo, restauración, mantenimiento, integridad, programación
├── u7/          exportación, colección, carga, consultas en ambos motores
├── u8/          esquema SQLite, cliente de la tablet, servidor de sincronización
├── evidencias/  salidas reales de la corrida
├── ejecutar_todo.py, lab.py
└── informe_tecnico.md, code_review_final.md, bitacora_ia.md, duia.md
```

Las entregas anteriores (`tpUnidad4/`, `UNIDAD 5/`, `Unidad 6/`, `unidad 7/`, `tp8/`) se conservan sin cambios; esta entrega las retoma, corrige lo encontrado en su revisión y las integra.
