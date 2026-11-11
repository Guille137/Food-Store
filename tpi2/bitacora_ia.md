# Bitácora de uso de IA — Segunda entrega (Unidades 4 a 8)

Herramienta: **Claude Code** (Anthropic), extensión de VS Code, con acceso al repositorio y a un servidor de laboratorio local (PostgreSQL 17.11, MongoDB 8.0.15, SQLite 3.43). Detalle en la [DUIA](duia.md).

Toda propuesta se ejecutó primero sobre una base **nueva** creada para la prueba, o dentro de una transacción que terminaba en `ROLLBACK`, con respaldo previo antes de la migración. Ningún dato personal real se envió al asistente: todos los datos son sintéticos (`@example.test`, `@foodstore.example`, teléfonos `5555`) y los logs se anonimizaron antes de analizarlos.

## Registro

| # | Unidad | Prompt o spec enviado | Respuesta relevante | Validación o corrección aplicada |
|---|---|---|---|---|
| 1 | Todas | Condiciones de la segunda entrega + repositorio: "Dame todo listo para entregar" | Mapa de los 15 objetivos contra lo existente: U4 sin esquema heredado ni migración, U5 solo el PDF de la consigna, U6 sin automatización ni verificación, U7 con 5 pedidos de ejemplo, U8 sin sincronización real | Se verificó leyendo cada carpeta y los PDF. Se decidió no reescribir entregas anteriores y crear `tpi2/` |
| 2 | U4 | [spec U4](../.kiro/specs/u4-migracion-legado/) | Esquema heredado con anomalías, validación de 9 DF, migración, verificación y reversión | Ejecutado: la DF `producto → rubro` daba 66 violaciones crudas y 0 canónicas; se agregó la corrección `Pizas` como tabla aprobada por una persona en lugar de que la migración "adivinara" |
| 3 | U4 | — | Primera versión: `mapa_pedido` con FK a pedidos que todavía no existían | **Error de la IA**, detectado por el ensayo con `ROLLBACK` (violación de FK). Se agregó la FK después de insertar los pedidos |
| 4 | U4 | — | Primera versión de `05_reversion.sql`: borraba pedidos antes que los mapas que los referencian | **Error de la IA**, detectado por la prueba de reversión: falló y no revirtió nada (no dejó daño gracias a la transacción). Corregido; la huella posterior es idéntica a la previa |
| 5 | U5 | [spec U5](../.kiro/specs/u5-roles-permisos/) | `04_roles.sql`, matriz de privilegios, verificación "ni más ni menos" | La verificación compara los 75 privilegios previstos contra el catálogo en ambos sentidos: 0 faltantes, 0 sobrantes |
| 6 | U5 | Prompt de auditoría de seguridad ([texto](u5/auditoria_permisos_ia.md#cómo-se-hizo)) | Once controles (A1–A11) y once hallazgos | **Permiso de más:** la versión inicial de `04_roles.sql`, generada por la IA, daba a `rol_reportes` la vista `tp5_pedidos_clientes` (nombre y apellido de clientes). Se detectó al revisar qué columnas devuelve cada vista otorgada. Se quitó (H3) |
| 7 | U5 | Ídem | Para H1 la solución directa era `GRANT UPDATE ON producto, categoria, pedido TO rol_app_escritura` | **Descartada por amplia:** permitiría a la aplicación cambiar precios y stock. Se eligió `SECURITY DEFINER` acotado |
| 8 | U5 | — | Al revocar todo a `PUBLIC` también se quitó `TEMPORARY` | **Error de la IA**, detectado por la prueba del mantenimiento (`REFRESH CONCURRENTLY` falló). Se otorgó `TEMPORARY` solo a `fs_owner`, no de nuevo a `PUBLIC` |
| 9 | U5 | Simulacro (`simulacro_incidente.py`) | Secuencia de fuerza bruta, lectura masiva y 7 escalamientos | Los 7 escalamientos fallaron; se verificó en el log y en `auditoria.*` |
| 10 | U5 | — | Primera versión de `anonimizar_log.py` sin enmascarar rutas | **Error de la IA**, detectado al inspeccionar el log "anonimizado": las rutas de `pg_hba.conf` contenían el usuario de Windows. Se agregó `[RUTA]` y su control en `restos()` |
| 11 | U5 | Prompt de reconstrucción ([texto](u5/informe_incidente.md#3-prompt-enviado-a-la-ia)) | Reconstrucción cronológica y seis medidas de contención | **Afirmación no sustentada:** vinculó la clave adivinada en la aplicación con el acceso a la base como `soporte_01`; el log no relaciona esas identidades. También concluyó "un único atacante" por una IP que es la del propio servidor. Ver contraste completo |
| 12 | U5 | Especificación de la consulta de equivalencia ([texto](u5/verificacion_equivalencia.md)) | Consultas sobre `anon.usuario_anon` y `usuario` | 29 filas iguales; `EXCEPT ALL` en ambos sentidos = 0 filas |
| 13 | U6 | [spec U6](../.kiro/specs/u6-mantenimiento/) | Scripts de respaldo, restauración, mantenimiento, integridad y programación | Pruebas negativas agregadas: respaldo fallido no deja archivo; respaldo alterado rechazado por SHA-256 |
| 14 | U6 | — | Simulacro de desastre | RTO 7,94 s. Al cuantificar lo perdido se encontró que `log_statement = mod` no registra `CALL`: los pedidos perdidos no están en el log. Se documentó como hallazgo |
| 15 | U7 | [spec U7](../.kiro/specs/u7-modelo-documental/) | Exportación, validador, 8 consultas en cada motor | Resultados comparados valor por valor: 8 de 8 idénticos. 8 documentos inválidos rechazados |
| 16 | U8 | [spec U8](../.kiro/specs/u8-sqlite-sincronizacion/) | Esquema SQLite, cliente de tablet y función de servidor | Primera versión no descontaba stock: **defecto de diseño**, detectado al plantear el caso de dos tablets (C8). Corregido con `FOR UPDATE` |
| 17 | U8 | — | `CALL tpi_registrar_pedido((SELECT …), …)` | **Error de la IA**: PostgreSQL no admite subconsultas como argumento de `CALL`. Detectado por la prueba C5 |
| 18 | Todas | Prompt de code review ([texto](code_review_final.md#alcance-y-método)) | 28 hallazgos sobre los scripts de la cursada | Cada uno reproducido o leído antes de decidir. 18 corregidos, 8 aceptados o mitigados, 2 mantenidos |

## El error más significativo

El de la reconstrucción del incidente (registro 11). La IA presentó como "probable" que la clave adivinada en el formulario web se reutilizó para entrar a la base como `soporte_01`. Suena razonable porque los dos hechos son consecutivos, pero el log no contiene ningún dato que vincule la cuenta de aplicación `persona_2` con el rol de base `soporte_01`; en el script eran identidades y claves distintas. Se detectó con un método simple: para cada afirmación de la respuesta se buscó la línea del log que la respaldaría, y para esa no había ninguna. Si se hubiera actuado sobre esa hipótesis, la investigación se habría concentrado en la aplicación y no en cómo se obtuvo la clave del rol de base.

## Límites de esta bitácora

- La misma herramienta que escribió el simulacro hizo la reconstrucción: no fue una prueba "a ciegas". Se recomienda repetir el prompt del registro 11 en una sesión nueva de OpenCode (herramienta indicada por la cátedra) entregando solo el log anonimizado, y agregar aquí esa respuesta.
- Las columnas de validación describen las pruebas ejecutadas. La decisión final sobre cada hallazgo debe ser confirmada por el equipo (firmas en [auditoría de permisos](u5/auditoria_permisos_ia.md#firma-del-equipo) y [code review](code_review_final.md#firma-del-equipo)).

## Historial de Git

Los commits de esta entrega están en la rama `segunda-entrega`, uno por unidad, con mensajes que describen qué se hizo y por qué (ver `git log`).
