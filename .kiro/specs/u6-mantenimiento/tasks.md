# Tareas — Plan de mantenimiento

- [x] 1. Respaldo verificado con rol de solo lectura, SHA-256, roles y retención (`tpi2/u6/respaldo.ps1`) — _Req. 1_
- [x] 2. Restauración con verificación de SHA-256, modos Prueba y Siniestro (`restaurar.ps1`) — _Req. 2.1–2.4_
- [x] 3. Prueba semanal de restauración del último respaldo (`prueba_restauracion.ps1`) — _Req. 2.5_
- [x] 4. Mantenimiento rutinario y verificación de integridad (`mantenimiento.sql`, `mantenimiento.ps1`, `verificar_integridad.sql`) — _Req. 3_
- [x] 5. Programación de tareas en modo simulación y registro (`programar_tareas.ps1`) — _Req. 4_
- [x] 6. Pruebas negativas: respaldo fallido sin archivo, respaldo alterado rechazado — _Req. 1.4, 2.1_
- [x] 7. Simulacro de desastre contra reloj con huella de contenido, verificación de permisos y prueba de humo (`ejecutar_todo.py`, paso `u6`) — _Req. 5_
- [x] 8. Informe post-incidente (`tpi2/u6/informe_post_incidente.md`) — _Req. 5.3_
