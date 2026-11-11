# Unidad 5 — Auditoría de seguridad del esquema de permisos asistida por IA

## Cómo se hizo

1. Se le pidió al asistente de IA (Claude Code, ver [DUIA](../duia.md)) que revisara [`04_roles.sql`](04_roles.sql) y el resto de los scripts de la Unidad 5 con este prompt:

   > Auditá el esquema de permisos de Food Store como lo haría un revisor de seguridad. Buscá: privilegios a PUBLIC, funciones SECURITY DEFINER peligrosas, roles con atributos de administración, opciones de re-otorgamiento, acceso a hashes de contraseña, DELETE/TRUNCATE en tablas del negocio, escritura sobre la auditoría, roles de login sin límite o sin SCRAM, tablas sin política y privilegios por defecto. Para cada clase de defecto escribí una consulta al catálogo que devuelva 0 filas si no hay hallazgos. Después proponé la corrección de cada hallazgo, indicando alternativas cuando existan.

2. La IA generó [`08_auditoria_seguridad.sql`](08_auditoria_seguridad.sql) (once controles, A1 a A11). Se leyó línea por línea, se ejecutó como superusuario sobre la base de laboratorio (solo lectura) y se revisó la salida ([evidencia](../evidencias/20261110_204915/u5_06_auditoria_seguridad.txt)).
3. Los hallazgos se discutieron uno por uno. La columna "Decisión del equipo" registra lo que se aplicó en el código y por qué.

## Resultado de los controles

| Control | Resultado |
|---|---|
| A1 Privilegios a PUBLIC | 0 filas |
| A2 SECURITY DEFINER sin `search_path` o con dueño superusuario | 0 filas (9 funciones DEFINER, todas de `fs_owner` con `search_path` fijo) |
| A3 Atributos de administración | 0 filas |
| A4 `ADMIN OPTION` | 0 filas |
| A5 `GRANT OPTION` | 0 filas |
| A6 Lectura del hash fuera de respaldo | 0 filas (A6b: solo `rol_respaldo` y `operador_respaldo`) |
| A7 DELETE/TRUNCATE en tablas del negocio | 0 filas |
| A8 Escritura en auditoría | 0 filas |
| A9 Login sin límite o sin SCRAM | 0 filas |
| A10 Tablas sin ningún rol que las lea | `entrega`, `repartidor`, `zona` (ver H6) |
| A11 Privilegios por defecto | rutinas sin PUBLIC; `anon` → reportes; `auditoria` → auditor |

## Hallazgos y decisiones

| # | Hallazgo | Propuesta de la IA | Decisión del equipo |
|---|---|---|---|
| H1 | Los triggers de reglas (`validar_producto_y_stock_detalle`, etc.) bloquean filas con `FOR SHARE`, que exige privilegio `UPDATE` sobre producto, categoría y pedido. Sin él, la aplicación no puede registrar pedidos. | Opción A, la directa: `GRANT UPDATE ON producto, categoria, pedido TO rol_app_escritura`. Opción B: funciones de trigger `SECURITY DEFINER` con dueño sin privilegios especiales. | **B.** La opción A le daría a la aplicación la capacidad de cambiar precios y stock. Con B la aplicación no recibe ningún `UPDATE` extra; el riesgo de DEFINER se acota con `search_path` fijo y dueño `fs_owner` (no superusuario), verificado por A2. |
| H2 | Nueve funciones `SECURITY DEFINER`: cada una es una puerta de elevación si tiene un error. | Mantener solo las imprescindibles y auditarlas con A2 en cada cambio. | **Aceptado.** Cada una está justificada en [design.md](../../.kiro/specs/u5-roles-permisos/design.md). A2 forma parte de la verificación. |
| H3 | `rol_reportes` podía leer `tp5_pedidos_clientes`, que expone **nombre y apellido** de clientes. La primera versión de `04_roles.sql`, generada por la IA, lo otorgaba: era un permiso de más. | Quitar el `GRANT` y usar `anon.pedido_anon`. | **Aceptado y aplicado.** Se quitó de `04_roles.sql` y de la matriz. Es el caso de permiso más amplio de lo necesario registrado en la [bitácora](../bitacora_ia.md). |
| H4 | `rol_respaldo` lee `password_hash` (vía `pg_read_all_data`). | Inevitable para un respaldo completo; alternativa: excluir la tabla del respaldo. | **Riesgo aceptado.** Excluirla haría el respaldo incompleto. Se compensa: rol sin escritura, respaldo con SHA-256 y fuera del repositorio (`.gitignore`), hashes bcrypt. |
| H5 | `fn_autenticar` calculaba el hash en los caminos "clave incorrecta" y "usuario inexistente", pero no en "cuenta inactiva" y "cuenta bloqueada": por tiempo de respuesta se podía saber qué cuentas existen. | Calcular un hash en todos los caminos. | **Aceptado y aplicado** en `01_usuario_autenticacion.sql`. |
| H6 | A10: `entrega`, `repartidor` y `zona` (creadas por la migración de la Unidad 4) no tenían política: nadie salvo el dueño las leía. | Otorgar `SELECT` a `rol_soporte`. | **Aceptado y aplicado.** Soporte responde "¿quién llevó mi pedido?". La aplicación web no las necesita. |
| H7 | `auditoria.registro` guarda la fila completa antes/después: incluye correo y teléfono de clientes. | Enmascarar también esas columnas. | **Descartado parcialmente.** El valor anterior es lo que permitió revertir el teléfono alterado en el simulacro. Se mantiene completo, legible solo por `rol_auditor`, y el hash sí se enmascara. Pendiente para producción: política de retención (12 meses). |
| H8 | `log_statement = all` para personas registra datos personales que aparecen en los `WHERE`. | Bajarlo a `mod`. | **Descartado.** Sin `all` no hubiera quedado registrada la lectura masiva del simulacro. Se trata el log como activo sensible ([informe_auditoria.md](informe_auditoria.md#4-el-log-es-un-activo-sensible)). |
| H9 | Al revocar todo a PUBLIC también se quitó `TEMPORARY`, y `REFRESH MATERIALIZED VIEW CONCURRENTLY` (que corre como dueño) falló en el mantenimiento. | Devolver `TEMPORARY` a PUBLIC. | **Descartado en esa forma.** Se otorgó `TEMPORARY` solo a `fs_owner`. Detectado por la prueba del plan de mantenimiento, no por la auditoría estática. |
| H10 | `pg_hba.conf` de laboratorio acepta a todos los roles desde `127.0.0.1` con SCRAM. | En producción, una línea por rol y red: `soporte_01` solo desde la VPN, `app_web` solo desde el servidor web. | **Pendiente para producción.** En el laboratorio todo es local. |
| H11 | `tablet_feria` puede crear pedidos sin límite a través de `sync.aplicar_solicitud`. | Límite de solicitudes por dispositivo y por hora. | **Aceptado como mejora futura.** Hoy: `CONNECTION LIMIT 5`, sin acceso a tablas y cada solicitud queda en `sync.solicitud` con su dispositivo. |

## Firma del equipo

Las decisiones de esta tabla se tomaron sobre la evidencia indicada. Antes de la defensa, cada integrante debe haberlas leído y poder explicarlas.

- [ ] Victoria Guzman
- [ ] Daniela Sosa
- [ ] Octavio Skumanic
- [ ] Sebastián Vivanco
- [ ] Guillermo Sanchez
