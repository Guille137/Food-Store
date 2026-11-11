# Unidad 5 — Simulacro de acceso indebido: reconstrucción e informe de contención

> Todo se ejecutó contra la base de laboratorio propia, con datos sintéticos. Nada de esto se aplica a sistemas de terceros.

Evidencia: [pasos ejecutados](../evidencias/20261110_204915/u5_09_simulacro_pasos.txt) · [log anonimizado](../evidencias/20261110_204915/u5_08_log_simulacro_anonimizado.txt) · [contención](../evidencias/20261110_204915/u5_10_contencion.txt).

## 1. Lo que se ejecutó

[`simulacro_incidente.py`](simulacro_incidente.py), invocado por `tpi2/ejecutar_todo.py`:

| Etapa | Acción | Previsto | Obtenido |
|---|---|---|---|
| 1 | 4 claves erróneas para `usuario3@foodstore.example` (cuenta de soporte) por `fn_autenticar`, vía `app_web` | Denegado | Denegado ×4 |
| 1 | Clave correcta (la de laboratorio) | Permitido | Permitido |
| 2 | 3 conexiones directas a PostgreSQL como `soporte_01` con clave errónea | Denegado | Denegado ×3 |
| 2 | Conexión como `soporte_01` con su clave | Permitido | Permitido |
| 3 | `SELECT * FROM usuario` | Denegado (hash) | Denegado |
| 3 | Lectura masiva de usuario (columnas permitidas) y de cliente (correo y teléfono) | Permitido | 40 y 360 filas |
| 4 | `UPDATE cliente SET nro_telefono = …` del cliente 10 | Permitido | Permitido |
| 5 | `GRANT rol_admin_datos TO soporte_01`, `SET ROLE rol_admin_datos`, `fn_resetear_password` de un administrador, `UPDATE usuario SET rol_aplicacion = 'ADMIN'`, `ALTER ROLE … SUPERUSER`, `DELETE FROM auditoria.registro`, `CREATE TABLE` | Denegado | **Denegado ×7** |

**El escalamiento falló en los siete intentos**: el esquema de la Parte A no tiene el defecto que la consigna pide buscar. Lo que sí funcionó es lo que el rol tiene permitido: leer contactos de clientes y cambiar un teléfono. Ese es el daño real del incidente.

## 2. Log anonimizado

Antes de mostrarle el log a la IA se pasó por [`anonimizar_log.py`](anonimizar_log.py): correos → `persona_N@anon.invalid`, teléfonos → `+00 0 00 0000-000N`, IP → `203.0.113.N` (rango de documentación), nombres de personas → `NOMBRE_N`, hashes → `[HASH]`, rutas locales → `[RUTA]/archivo`. La función `restos()` comprueba que no quede ningún correo, teléfono, IP, hash ni ruta original; la corrida la marcó como correcta. El reemplazo es consistente: `persona_2` es siempre la misma persona.

## 3. Prompt enviado a la IA

Se entregó **solo** el archivo anonimizado, con este texto y sin explicar qué se había ejecutado:

> Este es un fragmento del log de PostgreSQL y de tres tablas de auditoría de una base de datos de un comercio. Reconstruí qué ocurrió, en orden cronológico, y proponé una hipótesis de contención. Distinguí lo que el log muestra de lo que estás infiriendo.

## 4. Respuesta de la IA (completa)

> **Reconstrucción**
>
> 1. **20:49:30.693 – 20:49:31.064.** Desde `203.0.113.1`, a través de la aplicación `foodstore-web` (rol de base `app_web`), hubo cuatro intentos fallidos de inicio de sesión para `persona_2@anon.invalid` (`PASSWORD_INCORRECTA`), uno cada ~90 ms, y luego un ingreso exitoso. La vista `v_alerta_fuerza_bruta` lo marca: 4 fallos previos en menos de 0,4 s. La cadencia indica un proceso automatizado, no una persona escribiendo.
> 2. **20:49:31.139 – 20:49:31.279.** Tres conexiones directas a PostgreSQL como `soporte_01` fallan por contraseña (`FATAL: password authentication failed`). Mismo origen.
> 3. **20:49:31.468.** `soporte_01` se conecta con éxito usando `psql`. Es probable que el atacante haya usado la contraseña obtenida en el paso 1 en la cuenta de base de datos de esa misma persona (reutilización de claves).
> 4. **20:49:31.550.** Intenta `SELECT * FROM public.usuario`: denegado. Inmediatamente después ajusta la consulta a las columnas que sí puede ver y lee **todos los usuarios** (correo, nombre, apellido, rol). A las 20:49:31.725 lee **todos los clientes** con correo y teléfono: hay que considerar exfiltrados los datos de contacto de toda la cartera.
> 5. **20:49:31.931.** Modifica el teléfono del cliente 10 (`+00 0 00 0000-0002` → `…-0001` según `auditoria.registro`). Puede ser preparación de un fraude (desviar llamadas de verificación de ese cliente).
> 6. **20:49:32.013 – 20:49:32.448.** Intentos de escalamiento, todos rechazados: `GRANT rol_admin_datos`, `SET ROLE rol_admin_datos`, restablecer la clave de `persona_1` (probablemente un administrador), ascender a `persona_2` a `ADMIN`, `ALTER ROLE soporte_01 SUPERUSER`.
> 7. **20:49:32.638.** `DELETE FROM auditoria.registro`: intento de borrar huellas, rechazado. **20:49:32.728** `CREATE TABLE public.botin`: intento de preparar un lugar donde copiar datos, rechazado.
>
> Toda la secuencia duró unos 2 segundos y provino de una única IP, lo que sugiere un único atacante con un script.
>
> **Hipótesis de contención**
>
> 1. Deshabilitar el login de `soporte_01` (`ALTER ROLE soporte_01 NOLOGIN`) y terminar sus sesiones.
> 2. Bloquear `203.0.113.1` en el firewall o en `pg_hba.conf`.
> 3. Restablecer la contraseña de `persona_2` en la aplicación y obligar a cambiarla.
> 4. Revertir el teléfono del cliente 10 con el valor anterior de `auditoria.registro`.
> 5. Notificar a los clientes cuyos datos fueron leídos.
> 6. Revisar si `persona_1` recibió algún cambio y forzar el cambio de contraseña de todos los administradores.

## 5. Contraste con lo realmente ejecutado

| Afirmación de la IA | Veredicto | Por qué |
|---|---|---|
| Secuencia, horarios y cantidad de intentos de los pasos 1, 2, 4, 6 y 7 | **Correcto** | Coincide con el script, al milisegundo |
| Los siete escalamientos fueron rechazados | **Correcto** | Coincide con la tabla del punto 1 |
| Teléfono del cliente 10, valor anterior y nuevo | **Correcto** | Coincide con `auditoria.registro` |
| "Proceso automatizado" por la cadencia | **Correcto como inferencia**, bien marcada | Fue un script |
| "Usó la contraseña obtenida en el paso 1 en la cuenta de base de datos de esa misma persona" | **No lo sustenta el log** | El log no relaciona en ningún lado la cuenta de aplicación `persona_2` con el rol `soporte_01`. En el script son identidades distintas y la clave de `soporte_01` no fue la del paso 1. La IA unió dos hechos solo porque fueron consecutivos |
| "Leyó **todos** los usuarios y **todos** los clientes" | **No lo sustenta el log** | El log muestra el texto del `SELECT`, no cuántas filas devolvió. Fueron 40 y 360 porque no había `WHERE`, pero eso se deduce de la sentencia, no está registrado (límite que pgaudit tampoco resuelve del todo) |
| "Una única IP, un único atacante" | **Inferencia débil** | `203.0.113.1` es la anonimización de `127.0.0.1`: en el laboratorio todo el tráfico, incluido el legítimo, sale de la misma máquina. La IA no podía saberlo, pero tampoco debió concluirlo |
| "`persona_1` probablemente es un administrador" | **No lo sustenta el log** | Solo se ve que se intentó resetear su clave. (Sí lo es, pero por casualidad del script, no por evidencia) |
| `public.botin` "para copiar datos" | **Intención no verificable** | El log muestra el intento, no el motivo |
| Bloquear `203.0.113.1` | **Inaplicable tal cual** | Es una IP de documentación inventada por la anonimización; y la real es la del propio servidor |
| Omisión: no mencionó la conexión inicial como `postgres` al principio del log | **Omisión correcta** | Es la conexión del ejecutor del laboratorio, ajena al incidente; la IA no la distinguió, pero tampoco la usó |
| Omisión: no advirtió que el log **no** registra las lecturas de `app_web` ni las llamadas a `fn_autenticar` | **Omisión relevante** | Los intentos de login aparecen solo porque existe la tabla `auditoria.intento_login`. Con el log nativo solo, el paso 1 sería invisible |

**El error más significativo** es el del paso 3: presentar como "probable" una relación causal (clave robada en la app → acceso a la base) que el log no muestra. Si el equipo hubiera actuado sobre esa hipótesis, habría buscado la filtración en la aplicación y no en cómo se obtuvo la clave de `soporte_01`. Se detectó contrastando cada afirmación con la línea del log que la respaldaría: para esa no había ninguna.

## 6. Decisión de contención del equipo

La decisión es del equipo, tomada sobre la evidencia del log y las tablas de auditoría; no es una ejecución automática de lo que sugirió la IA. Se probó en el laboratorio con [`09_contencion.sql`](09_contencion.sql):

| Medida | Por qué | Probada |
|---|---|---|
| `ALTER ROLE soporte_01 NOLOGIN` y cierre de sesiones | Es la identidad usada para leer y modificar; cortarla detiene el daño sin afectar al resto del personal | Sí: el siguiente intento de conexión falla con `not permitted to log in` |
| Clave temporal aleatoria para `persona_2` con cambio obligatorio (`fn_resetear_password`) | Su clave de aplicación fue adivinada (el log sí lo muestra: 4 fallos y un acierto) | Sí: la clave adivinada deja de servir |
| Restaurar el teléfono del cliente 10 desde el valor "antes" de `auditoria.registro` | Revertir solo lo que el rol comprometido cambió, con evidencia | Sí |
| Rotar la clave de `soporte_01` antes de rehabilitarlo y revisar cómo se obtuvo | El log no muestra el origen de esa clave: hay que investigarlo con la persona | Rehabilitado con clave nueva al final del simulacro |
| Restringir `pg_hba.conf`: `soporte_01` solo desde la red interna o VPN | Hallazgo H10 | Pendiente (producción) |
| Tratar la lectura de 360 contactos como posible incidente de datos personales: evaluar el aviso a los titulares y a la autoridad de control según la Ley 25.326 | La lectura ocurrió, aunque no hay evidencia de que los datos salieran del equipo | Decisión organizativa, fuera del laboratorio |

**Lo que el equipo descartó de la propuesta de la IA:** bloquear la IP (es la de documentación y, en realidad, la del propio servidor) y forzar el cambio de clave de *todos* los administradores (no hay evidencia de que alguno haya sido comprometido; el intento sobre `persona_1` falló).

**Mejoras derivadas:** bloqueo por cantidad de fallos también para los roles de base (hoy lo tiene solo `fn_autenticar`; PostgreSQL no lo trae de forma nativa: se propone `auth_delay` o fail2ban sobre el log), y alertas sobre `v_alerta_fuerza_bruta` revisadas por `auditor_01`.
