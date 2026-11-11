# Requisitos — Usuarios, roles, permisos y auditoría (Unidad 5)

## Introducción

Food Store necesita que cada persona y cada sistema que se conecta a la base pueda hacer exactamente lo que su función exige y nada más, y que lo que ocurra quede registrado de forma que un incidente pueda reconstruirse.

## Requisito 1 — Mínimo privilegio

1. EL SISTEMA DEBERÁ crear un rol de grupo por función (`rol_app_lectura`, `rol_app_escritura`, `rol_soporte`, `rol_reportes`, `rol_auditor`, `rol_respaldo`, `rol_admin_datos`, `rol_sync_movil`) y roles de login que solo heredan de su grupo.
2. NINGÚN rol de login DEBERÁ tener `SUPERUSER`, `CREATEROLE`, `CREATEDB`, `REPLICATION`, `BYPASSRLS`, `ADMIN OPTION` ni `GRANT OPTION`.
3. EL SISTEMA DEBERÁ quitar a `PUBLIC` todo privilegio sobre la base, los esquemas, las tablas y las funciones del proyecto.
4. EL SISTEMA DEBERÁ incluir al menos un permiso a nivel de columna (`rol_soporte` lee `usuario` sin `password_hash`).
5. CUANDO se cree una tabla nueva en `public`, NINGÚN rol de aplicación DEBERÁ poder accederla hasta que se le otorgue explícitamente; CUANDO se cree una función nueva, `PUBLIC` NO DEBERÁ poder ejecutarla (`ALTER DEFAULT PRIVILEGES`).
6. CUANDO se ejecute `06_verificar_permisos.sql`, los privilegios del catálogo DEBERÁN coincidir exactamente con la matriz de design.md (cero faltantes y cero sobrantes).

## Requisito 2 — Autenticación de usuarios internos

1. EL SISTEMA DEBERÁ guardar las contraseñas solo como hash bcrypt.
2. `fn_autenticar` DEBERÁ registrar cada intento en `auditoria.intento_login` y bloquear la cuenta 15 minutos tras 5 fallos seguidos.
3. `fn_autenticar` NO DEBERÁ lanzar errores con la contraseña recibida ni permitir distinguir por tiempo de respuesta si una cuenta existe.
4. `fn_resetear_password` NO DEBERÁ recibir la clave nueva como parámetro.

## Requisito 3 — Auditoría

1. EL SERVIDOR DEBERÁ registrar conexiones, desconexiones y toda sentencia de modificación o DDL, con momento, rol, base, origen y aplicación.
2. EL SISTEMA DEBERÁ registrar fila por fila los cambios sobre usuario, cliente, producto, categoría y el estado de pedido, con valor anterior y posterior.
3. La auditoría DEBERÁ ser de solo agregado: ningún rol (ni su dueño, salvo deshabilitando el trigger) podrá modificarla o borrarla.
4. Las contraseñas de los roles NO DEBERÁN quedar en el log del servidor.

## Requisito 4 — Simulacro de acceso indebido

1. CUANDO se ejecute el simulacro (fallos de login, ingreso, lectura masiva, intento de escalamiento), cada intento de escalamiento DEBERÁ fallar.
2. EL SISTEMA DEBERÁ permitir reconstruir la secuencia solo con el log y las tablas de auditoría.
3. El log DEBERÁ anonimizarse antes de entregarlo a un asistente de IA.
4. La decisión de contención DEBERÁ ser tomada y documentada por el equipo.

## Requisito 5 — Datos anonimizados

1. EL SISTEMA DEBERÁ ofrecer copias anonimizadas (`anon.*`) con seudónimos deterministas no reversibles sin la sal.
2. CUANDO se compare un agregado sobre `anon.usuario_anon` con el mismo agregado sobre `usuario`, los resultados DEBERÁN ser idénticos.
