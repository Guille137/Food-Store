# Tareas — Food Store sin conexión

1. Crear las cinco tablas locales STRICT (`producto_cache`, `pedido_borrador`, `item_borrador`, `cola_sync`, `snapshot_servidor`), restricciones y claves foráneas; demostrar COMMIT, ROLLBACK, catálogo offline (C1) y errores de integridad (C7).
2. Crear en una copia de pruebas PostgreSQL la vista `v_snapshot_movil`; exportar/importar el CSV sin información personal.
3. Implementar el semáforo SQLite para solicitudes pendientes; ejecutar `cargar_cache.sql` tras cada snapshot nuevo y ejecutar C2–C6 con instantáneas renovadas para comparar conteos/stock del servidor.
4. Documentar el mapa de motores, mantenimiento, hallazgos revisados, bitácora de IA y pasos reproducibles.
