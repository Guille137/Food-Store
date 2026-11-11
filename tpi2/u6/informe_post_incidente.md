# Unidad 6 — Informe post-incidente del simulacro de desastre

| | |
|---|---|
| Fecha | 10/11/2026, 20:49:55 (hora de Buenos Aires) |
| Escenario | Pérdida total de la base de producción (`DROP DATABASE … WITH (FORCE)`) |
| Respaldo utilizado | El último respaldo diario: 220.543 bytes, terminado a las 20:49:43 |
| Resultado | Servicio restablecido, contenido idéntico al del respaldo |
| **RTO observado** | **7,94 s** (objetivo 15 min) |
| **RPO observado** | **11,9 s** (objetivo 24 h) |
| Datos perdidos | 3 pedidos y 1 cambio de precio, posteriores al respaldo |
| Evidencia | [`u6_05_simulacro_desastre.txt`](../evidencias/20261110_204915/u6_05_simulacro_desastre.txt), [`.json`](../evidencias/20261110_204915/u6_05_simulacro_desastre.json) |

## Línea de tiempo (reloj iniciado al provocar el desastre)

| t (s) | Hito |
|---:|---|
| 0,00 | Después del respaldo se registran 3 pedidos (`app_web`) y se sube un precio (`admin_datos`). Se elimina la base |
| 0,28 | Base eliminada |
| 0,47 | Detección: la aplicación recibe `database … does not exist` |
| 7,33 | `restaurar.ps1 -Modo Siniestro` termina: SHA-256 verificado (0,17 s), `pg_restore --create` (4,19 s), `ANALYZE` (1,05 s), integridad (1,04 s) |
| 7,52 | La huella de contenido es **idéntica** a la tomada al respaldar (todas las tablas, filas y md5) |
| 7,67 | Permisos: coinciden con la matriz de la Unidad 5, incluido `CONNECT` a nivel base |
| 7,94 | Prueba de humo: `app_web` lee el catálogo (68 productos) y registra un pedido (revertido) |

## Qué funcionó

- El respaldo era restaurable: se había probado con la restauración semanal y el SHA-256 confirmó que no estaba alterado.
- `--create` recreó la base con sus permisos. Una restauración sobre una base creada a mano habría perdido los `GRANT CONNECT` y la aplicación no hubiera podido conectarse.
- La verificación es automática: no se dio por buena la restauración "a ojo".

## Qué se perdió y por qué

Los 3 pedidos y el cambio de precio ocurrieron después del respaldo: el RPO es exactamente el tiempo desde el último respaldo. En el laboratorio fueron 12 segundos; con el respaldo diario programado a las 02:00, un desastre a las 23:00 perdería **21 horas** de ventas.

Al intentar reconstruir lo perdido desde el log del servidor: el cambio de precio **sí** está (`log_statement = mod` registra el `UPDATE`), pero los pedidos **no**, porque se registran con `CALL tpi_registrar_pedido(...)` y `log_statement = mod` no clasifica `CALL` como modificación. Hallazgo importante: el log no sirve para recuperar ventas.

## Comparación con el simulacro anterior (Unidad 6, 02/11/2026)

| | Anterior | Este |
|---|---|---|
| RTO | 16 min 35 s (objetivo superado) | 7,94 s |
| Causa de la demora | `pg_dump` fuera del PATH; primera restauración dejó la base vacía y no se detectó hasta validar | Ruta parametrizada; restauración, verificación y prueba de humo en una sola secuencia |
| Verificación | Conteos manuales | Huella completa + integridad + permisos + prueba de humo |

## Acciones

| # | Acción | Responsable | Estado |
|---|---|---|---|
| 1 | Archivar WAL (`archive_mode = on`) y respaldo base semanal con `pg_basebackup` para recuperar hasta el instante previo al desastre (PITR): RPO de minutos | Equipo de datos | Propuesta |
| 2 | Registrar en `auditoria` también las altas de pedidos (o `log_statement = all` para `app_web` si se elimina el paso de contraseñas en `fn_autenticar` por SQL) | Equipo de datos | Propuesta |
| 3 | Guardar una copia del respaldo fuera del servidor (otro disco u otro sitio) | Operaciones | Propuesta |
| 4 | Alerta si el último respaldo tiene más de 26 h (`prueba_restauracion.ps1` ya lo avisa) | Operaciones | Implementado (aviso) |
| 5 | Repetir el simulacro con el volumen de producción para conocer el RTO real | Equipo de datos | Pendiente |
