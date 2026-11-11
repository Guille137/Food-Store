# Diseño — Roles y permisos de Food Store

## Roles y justificación

| Rol | Login | Habilita | Por qué esa operación y no otra |
|---|---|---|---|
| `fs_owner` | no | Es dueño de todos los objetos | Las funciones `SECURITY DEFINER` corren con sus privilegios, no con los de un superusuario |
| `rol_app_lectura` | no | Leer catálogo (`categoria`, `producto`, `tp5_productos_vigentes`) | La vitrina web no necesita ver clientes ni pedidos |
| `rol_app_escritura` | no | Alta de clientes, pedidos solo por `tpi_registrar_pedido`, cambio de estado, autenticar | La aplicación no inserta pedidos a mano: así siempre se aplican las reglas del procedimiento |
| `rol_soporte` | no | Leer clientes, pedidos y reparto; corregir teléfono y estado; ver usuarios **sin hash** | Atiende consultas; no cambia precios ni identidades |
| `rol_reportes` | no | Solo vistas agregadas y `anon.*` | Analiza ventas sin ver datos personales |
| `rol_auditor` | no | Leer `auditoria.*` | Revisa lo ocurrido; no toca datos del negocio |
| `rol_respaldo` | no | `pg_read_all_data` | `pg_dump` necesita leer todo; no puede escribir |
| `rol_admin_datos` | no | Altas y cambios de catálogo y personal, baja lógica, restablecer claves | Sin `DELETE` (las bajas son lógicas) y sin leer el hash |
| `rol_sync_movil` | no | Leer `sync.v_snapshot_movil` y ejecutar `sync.aplicar_solicitud` | La tablet propone, el servidor dispone (Unidad 8) |
| `app_web`, `admin_datos`, `soporte_01`, `analista_01`, `auditor_01`, `operador_respaldo`, `tablet_feria` | sí | Heredan solo de su grupo, con límite de conexiones | Una identidad por persona o sistema para que el log diga quién fue |

## Matriz de privilegios

| Rol | Base / esquemas | Tablas y vistas | Columnas | Rutinas |
|---|---|---|---|---|
| rol_app_lectura | CONNECT; USAGE public | SELECT categoria, producto, tp5_productos_vigentes | — | — |
| rol_app_escritura | (hereda lectura) | SELECT cliente, pedido, detalle_pedido; INSERT cliente | UPDATE cliente(nombre, apellido, nro_telefono); UPDATE pedido(estado) | tpi_registrar_pedido, tpi_total_pedido, fn_autenticar |
| rol_soporte | CONNECT; USAGE public | SELECT categoria, producto, cliente, pedido, detalle_pedido, entrega, repartidor, zona | SELECT usuario(todas menos password_hash, intentos_fallidos, debe_cambiar_password); UPDATE cliente(nro_telefono); UPDATE pedido(estado) | tpi_total_pedido |
| rol_reportes | CONNECT; USAGE public, unidad4, anon | SELECT tp5_productos_vigentes, tp5_detalles_productos, tp5_facturacion_mensual, unidad4.ventas_categoria_diaria, unidad4.top_categorias_materializado, anon.usuario_anon, anon.cliente_anon, anon.pedido_anon | — | — |
| rol_auditor | CONNECT; USAGE auditoria | SELECT auditoria.registro, intento_login, v_alerta_fuerza_bruta, v_actividad_por_rol | — | — |
| rol_admin_datos | (hereda escritura y soporte) | INSERT categoria, producto | UPDATE categoria(nombre, activo); producto(nombre, precio_lista, stock, activo, categoria_id); usuario(nombre, apellido, rol_aplicacion, activo) | tpi_baja_producto, fn_resetear_password |
| rol_respaldo | CONNECT | (pg_read_all_data) | — | — |
| rol_sync_movil | CONNECT; USAGE sync | SELECT sync.v_snapshot_movil | — | sync.aplicar_solicitud |

Esta matriz está transcripta en `tpi2/u5/06_verificar_permisos.sql`, que la compara contra el catálogo en ambos sentidos.

## Decisiones

- **SECURITY DEFINER acotado.** Los triggers de reglas usan `FOR SHARE`, que exige privilegio `UPDATE`; la sincronización de la Unidad 4 hace `REFRESH`, que exige ser dueño. En lugar de dar esos privilegios a la aplicación, esas funciones pasan a `SECURITY DEFINER` con dueño `fs_owner` (no superusuario) y `search_path` fijo.
- **Objetos futuros.** En `public` no hay permisos por defecto: una tabla nueva obliga a decidir quién la ve. En `anon` lo nuevo es para reportes y en `auditoria` para el auditor.
- **Log por persona.** `soporte_01`, `admin_datos` y `analista_01` tienen `log_statement = all`. `app_web` no, porque registraría las contraseñas que recibe `fn_autenticar`.
- **Contraseñas fuera del repositorio.** `04_roles.sql` las recibe como variables de psql y silencia el log durante el `ALTER ROLE`.
- **Respaldo lee el hash.** Es inevitable para un respaldo completo; se compensa con un rol sin escritura y la protección del archivo de respaldo.
