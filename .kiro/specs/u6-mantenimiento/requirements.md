# Requisitos — Plan de mantenimiento (Unidad 6)

## Introducción

La base de Food Store debe poder recuperarse ante la pérdida total en menos de 15 minutos (RTO) perdiendo como máximo un día de datos (RPO), y mantenerse sana sin intervención manual diaria. Esta spec reemplaza a `Unidad 6/tpunidad6/SPEC_U6.md` y corrige los problemas encontrados en esa entrega.

## Requisito 1 — Respaldo programado

1. EL SISTEMA DEBERÁ generar un respaldo `pg_dump -Fc` diario con nombre fechado, conectándose con el rol de solo lectura `operador_respaldo`.
2. CUANDO termine el respaldo, EL SISTEMA DEBERÁ verificar el código de salida, que el tamaño sea mayor que cero y que `pg_restore --list` pueda leer el índice.
3. EL SISTEMA DEBERÁ guardar el SHA-256 del archivo y la definición de roles sin contraseñas.
4. SI el respaldo falla, ENTONCES EL SISTEMA DEBERÁ terminar con código de error y no dejar un archivo que parezca válido.
5. EL SISTEMA DEBERÁ eliminar los respaldos con más de 14 días de esa base.
6. EL SISTEMA NO DEBERÁ contener ni solicitar contraseñas (archivo de contraseñas de PostgreSQL y `--no-password`).

## Requisito 2 — Restauración probada

1. CUANDO se restaure, EL SISTEMA DEBERÁ verificar primero el SHA-256 y rechazar un archivo alterado.
2. En modo prueba, EL SISTEMA DEBERÁ restaurar en una base nueva con otro nombre y nunca tocar la original.
3. En modo siniestro, EL SISTEMA DEBERÁ recrear la base con su nombre original y sus permisos, y negarse si la base todavía existe.
4. CUANDO termine la restauración, EL SISTEMA DEBERÁ actualizar estadísticas y verificar integridad.
5. EL SISTEMA DEBERÁ ejecutar una restauración de prueba semanal del respaldo más reciente y eliminar luego la base temporal.

## Requisito 3 — Tareas rutinarias

1. Semanalmente, EL SISTEMA DEBERÁ ejecutar `VACUUM (ANALYZE)`, refrescar las vistas materializadas y las copias anónimas, e informar filas muertas, tamaños, índices sin uso y transacciones largas.
2. EL SISTEMA NO DEBERÁ usar `VACUUM FULL` de rutina.
3. EL SISTEMA DEBERÁ verificar la integridad física (amcheck, checksums de página) y lógica (reglas del negocio no cubiertas por restricciones) y fallar si encuentra un problema.

## Requisito 4 — Automatización

1. EL SISTEMA DEBERÁ registrar las tres tareas en el Programador de tareas de Windows: respaldo diario 02:00, mantenimiento domingo 03:00, restauración de prueba domingo 04:00.
2. Sin el parámetro `-Registrar`, el script de programación NO DEBERÁ modificar el equipo.

## Requisito 5 — Simulacro de desastre

1. EL SISTEMA DEBERÁ medir, contra reloj, desde la pérdida de la base hasta que la aplicación vuelve a operar.
2. CUANDO termine la restauración, el contenido DEBERÁ ser idéntico al del momento del respaldo y los permisos DEBERÁN coincidir con la matriz de la Unidad 5.
3. EL SISTEMA DEBERÁ cuantificar los datos perdidos y documentar un informe post-incidente.
