# Unidad 5 — Informe de auditoría

Evidencia: [`u5_02_config_auditoria.txt`](../evidencias/20261110_204915/u5_02_config_auditoria.txt), [`u5_07_log_auditoria_prueba.txt`](../evidencias/20261110_204915/u5_07_log_auditoria_prueba.txt).

## 1. Parámetros activados

Aplicados con [`05_config_auditoria.sql`](05_config_auditoria.sql) (`ALTER SYSTEM` + `pg_reload_conf()`, sin reinicio):

| Parámetro | Valor | Para qué |
|---|---|---|
| `logging_collector` | `on` | Escribir el log a archivo (se fija al crear el servidor: requiere reinicio) |
| `log_connections` | `on` | Quién entra, desde dónde y con qué método |
| `log_disconnections` | `on` | Cuándo sale y cuánto duró la sesión |
| `log_statement` | `mod` | Toda escritura y todo DDL, incluidos `GRANT`/`REVOKE` |
| `log_line_prefix` | `%m [%p] rol=%u base=%d origen=%h app=%a ` | Cada línea dice cuándo, quién, dónde, desde dónde y con qué programa |
| `log_min_error_statement` | `error` | El texto de las sentencias rechazadas (permiso denegado) |
| `log_parameter_max_length` / `_on_error` | `0` | No registrar valores de parámetros enlazados (una contraseña enviada como parámetro no llega al log) |
| `password_encryption` | `scram-sha-256` | Claves de los roles con SCRAM |
| `log_statement` por rol | `all` para `soporte_01`, `admin_datos`, `analista_01` | Las personas quedan registradas también cuando **leen** |

Además, auditoría por fila dentro de la base ([`02_auditoria.sql`](02_auditoria.sql)): `auditoria.registro` guarda valor anterior y posterior de cada cambio en usuario, cliente, producto, categoría y estado de pedido; `auditoria.intento_login` guarda cada intento de `fn_autenticar`. Ambas son de solo agregado.

## 2. Secuencia de prueba y fragmento de log

Lectura (`soporte_01`), inserción (`app_web`), actualización (`soporte_01`) y un inicio de sesión fallido. Fragmento real (base y rutas abreviadas):

```text
20:49:28.973 [27844] rol=soporte_01 origen=127.0.0.1 app=[unknown] LOG:  connection authorized: user=soporte_01 ... application_name=prueba-auditoria
20:49:28.977 [27844] rol=soporte_01 origen=127.0.0.1 app=prueba-auditoria LOG:  statement: SELECT count(*) FROM public.cliente
20:49:28.981 [27844] rol=soporte_01 ... LOG:  disconnection: session time: 0:00:00.033 user=soporte_01 ...
20:49:29.056 [9724]  rol=app_web    ... LOG:  statement: INSERT INTO public.cliente (correo_electronico, nombre, apellido) VALUES ('prueba.auditoria@example.test', ...
20:49:29.141 [25504] rol=soporte_01 ... LOG:  statement: UPDATE public.cliente SET nro_telefono = '+54 9 11 5555-7777' WHERE correo_electronico = 'prueba.auditoria@example.test'
20:49:29.219 [48456] rol=soporte_01 origen=127.0.0.1 app=[unknown] FATAL:  password authentication failed for user "soporte_01"
```

Y la auditoría por fila de los mismos hechos, leída con `auditor_01`:

```text
 hora         | rol_sesion | origen    | aplicacion       | tabla          | operacion | tel_despues
 20:49:29.059 | app_web    | 127.0.0.1 | prueba-auditoria | public.cliente | INSERT    |
 20:49:29.147 | soporte_01 | 127.0.0.1 | prueba-auditoria | public.cliente | UPDATE    | +54 9 11 5555-7777
```

## 3. Qué sirve y qué queda fuera

| Pregunta | Dónde está |
|---|---|
| **Quién** | `rol=` del prefijo; `rol_sesion` en la tabla. Por eso cada persona tiene su propio rol de login |
| **Qué** | Texto de la sentencia (`statement:`); en la tabla, fila exacta con antes y después |
| **Cuándo** | `%m`, con milisegundos y zona horaria |
| **Desde dónde** | `origen=` (IP) y `app=` (programa que se identificó) |
| **Resultado** | `ERROR`/`FATAL` con el motivo |

Fuera del alcance del mecanismo nativo:

- **Lecturas de `app_web`.** Con `log_statement = mod` no se registran los `SELECT` de la aplicación, ni las llamadas a `fn_autenticar` (que se ven solo en `auditoria.intento_login`).
- **`CALL`.** `log_statement = mod` no clasifica `CALL` como modificación: los pedidos registrados con `tpi_registrar_pedido` **no aparecen** en el log del servidor. Lo comprobó el simulacro de desastre (Unidad 6): el cambio de precio quedó registrado y los tres pedidos perdidos no.
- **Qué filas se leyeron.** El log dice que se ejecutó `SELECT ... FROM cliente`, no cuántas filas ni cuáles.
- **Objeto real.** Si la sentencia usa una vista o una función, el log muestra el texto, no las tablas que tocó por dentro.

Eso es lo que agrega **pgaudit**: registro por clase de sentencia (`READ`, `WRITE`, `FUNCTION`, `ROLE`, `DDL`), auditoría por objeto (`pgaudit.role`: solo las tablas sensibles) y una línea por cada objeto alcanzado aunque la sentencia sea indirecta. No se instaló porque no está incluido en la distribución de PostgreSQL para Windows usada.

## 4. ¿El log es un activo sensible?

Sí. Contiene correos y teléfonos dentro de las sentencias (`WHERE correo_electronico = '...'`), nombres de roles, IP y horarios de trabajo, y basta para planificar un ataque. Debe poder leerlo solo la cuenta de sistema del servicio de PostgreSQL y el rol de auditoría (en PostgreSQL, `pg_read_server_files` o `pg_monitor` para `pg_current_logfile()`; nunca `PUBLIC`), con permisos de archivo 0600 en Linux o ACL equivalente en Windows, rotación y retención definidas, y copia a un destino donde quien administra la base no pueda borrarlo. Antes de compartir un fragmento —incluso con un asistente de IA— se anonimiza ([`anonimizar_log.py`](anonimizar_log.py)).
