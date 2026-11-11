# TP8 — Food Store en la feria

**Grupo:** Victoria Guzman, Daniela Sosa, Octavio Skumanic, Sebastián Vivanco, Guillermo Sanchez

SQLite conserva el catálogo copiado y los borradores; PostgreSQL sigue siendo la fuente de verdad. `SIMULADO_APROBADO` indica que los datos coinciden con la instantánea: no crea una venta.

## Contenido de la entrega

- `servidor/snapshot_postgresql.sql`: vista móvil que adapta el catálogo real del proyecto.
- `servidor/casos_postgresql.md`: preparación y comandos para C2–C6 en una copia de pruebas.
- `movil/schema_sqlite.sql`: esquema SQLite con las tablas `STRICT` del TP, claves y restricciones.
- `movil/pruebas_sqlite.sql`: transacciones, catálogo sin conexión y controles C7.
- `movil/snapshot_sqlite.sql`: tabla que recibe el CSV.
- `movil/cargar_cache.sql`: actualiza el catálogo local y conserva lápidas.
- `movil/servidor_snapshot.csv`: instantánea final del escenario C4, con el producto 1 dado de baja. Para repetir otros casos, exportá una instantánea nueva desde PostgreSQL.
- `movil/semaforo.sql`: resuelve solo las solicitudes `PENDIENTE` en SQLite.
- `movil/pruebas_casos_sqlite.sql`: fixture local reproducible de C2–C6.
- `movil/foodstore_movil.db`: base local con los casos preparados y C6 resuelto.
- `docs/informe.pdf`: informe de consignas y resultados comprobados.
- `docs/kiro/`: requisitos EARS, diseño y tareas revisados en Kiro.
- `docs/bitacora_ia.md` y `docs/DUIA.md`: registro y declaración de IA.

## Transparencia sobre herramientas

Codex preparó, comprobó y revisó manualmente los scripts de TP8; Kiro revisó los requisitos, el diseño y las tareas. Se intentó usar OpenCode en modo Plan, pero la sesión quedó sin responder. La revisión del informe se limitó a TP8 y no sustituye el requisito de revisar scripts de varias unidades con OpenCode. No se declara ese requisito como completado.

