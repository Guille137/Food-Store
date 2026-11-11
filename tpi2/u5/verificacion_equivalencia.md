# Unidad 5 — Anonimización y verificación de equivalencia

Script: [`03_usuario_anon.sql`](03_usuario_anon.sql). Evidencia: [`u5_11_equivalencia_anonimizacion.txt`](../evidencias/20261110_204915/u5_11_equivalencia_anonimizacion.txt).

## Técnica

| Dato | Tratamiento en `anon.*` |
|---|---|
| Identificador de usuario o cliente | Seudónimo determinista `usr_`/`cli_` + 12 hex de `sha256(id:sal)`. La sal está en `seguridad.sal`, que solo lee `fs_owner` |
| Correo | Reemplazado por `<seudónimo>@anon.invalid` |
| Nombre, apellido, teléfono, hash | Suprimidos (de teléfono queda solo "tiene / no tiene") |
| Fecha de alta | Generalizada a mes |
| Rol, estado, forma de pago, importes | Se conservan: son lo que se analiza |

Las copias son vistas **materializadas**: un analista las lee sin tener permiso sobre las tablas reales ni sobre la función de seudónimos (se comprobó: `analista_01` lee `anon.cliente_anon` y recibe *permission denied* en `cliente` y en `seguridad.sal`).

## Consulta especificada y su equivalente

Especificación dada a la IA: *"cantidad de usuarios y de usuarios activos, por rol de aplicación y por mes de alta (hora de Buenos Aires), sobre `anon.usuario_anon`; y la consulta equivalente sobre la tabla real `usuario`"*.

```sql
-- Sobre la copia anónima
SELECT rol_aplicacion, mes_alta, count(*) AS usuarios, count(*) FILTER (WHERE activo) AS activos
FROM anon.usuario_anon GROUP BY 1, 2 ORDER BY 1, 2;

-- Sobre la tabla real
SELECT rol_aplicacion,
       date_trunc('month', fecha_alta AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
       count(*) AS usuarios, count(*) FILTER (WHERE activo) AS activos
FROM public.usuario GROUP BY 1, 2 ORDER BY 1, 2;
```

## Resultado

Las dos consultas devuelven las mismas 29 filas (ambos resultados completos, uno debajo del otro, en la evidencia). La equivalencia no se afirma mirando: `seguridad.v_equivalencia_usuario` compara ambos agregados con `EXCEPT ALL` en los dos sentidos y devolvió **0 filas**. Además: 360 clientes reales → 360 seudónimos distintos, y los 2.398 pedidos de `anon.pedido_anon` se enlazan con su cliente seudonimizado (2.398 de 2.398): el seudónimo es uno a uno y conserva las relaciones.

## Qué nunca debe salir hacia un asistente de IA sin este proceso

Correos, teléfonos, nombres y apellidos de clientes y del personal, hashes de contraseñas, contraseñas de roles, direcciones IP y rutas del equipo que aparecen en los logs, y cualquier combinación que permita identificar a una persona (por ejemplo, historial de pedidos con fecha exacta de un cliente identificable). Para trabajar con IA alcanza con el esquema, datos sintéticos o las copias de `anon`, y fragmentos de log pasados por `anonimizar_log.py`.
