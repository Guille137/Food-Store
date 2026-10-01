# Unidad 4 — FNBC y desnormalización controlada

Grupo: Octavio Skumanic, Sebastián Vivanco, Victoria Guzman, Daniela Sosa, Guillermo Sanchez

Esta carpeta corresponde a la **Unidad 4**. `tp4/` conserva el TP anterior de optimización y no se reemplaza.

## Entrega y recorrido

1. [Informe breve en PDF](informe_fnbc_desnormalizacion.pdf): análisis de dependencias, anomalías, descomposición, justificación y capturas de planes.
2. [Parte 1: FNBC](tp_fnbc_control_lote.sql): tablas maestras, instancia original, descomposición, FK, vista y verificación de migración.
3. [Parte 2: desnormalización](tp_desnormalizacion_top_categorias.sql): materializada, sincronización automática, consultas comparables y auditoría.
4. [Verificación reproducible](verificar.py) y [evidencias reales](evidencias/): pruebas funcionales, concurrencia, planes y tiempos.

## Adaptación al esquema existente

Ejecución de referencia: [20260930_190238_612510](evidencias/20260930_190238_612510/resultado.json), PostgreSQL 17.11, **66 comprobaciones correctas**. Lectura: mediana de **114,230 ms → 0,040 ms**. UPDATE de seis detalles: **0,638 ms → 209,583 ms** al incorporar el refresh. Auditoría final: **0 filas**. Los planes completos se adjuntan en TXT, JSON y capturas PNG; el informe explica el método y las limitaciones.

La consulta orientativa del enunciado utiliza nombres que no están en `schema.sql`. Aquí se usan `id_pedido`, `id_producto`, `id_categoria` y `cantidad * precio_unitario`. Pedido y detalle no tienen `eliminado`: se incluyen las filas existentes sin agregar columnas ficticias ni cambiar las reglas anteriores. Las bajas lógicas de producto/categoría conservan la venta histórica; no se filtra por `activo` ni por estado del pedido, porque el reporte pedido no impone ese filtro. Así, se conserva la semántica de sumar detalles de pedidos existentes, no se redefine el reporte como ventas confirmadas.

El día comercial se fija en `America/Argentina/Buenos_Aires`. Se usa un intervalo desde medianoche inclusive hasta la siguiente medianoche exclusiva. Los empates se ordenan por nombre para obtener el mismo top 5. El nombre de categoría es UNIQUE en el esquema base.

## Reproducir todas las pruebas

Requisitos: PostgreSQL **16 o superior**, Python y las dependencias del `requirements.txt` principal. Usar un servidor local de pruebas y un usuario con permiso de crear bases. La contraseña puede resolverse mediante el archivo de contraseñas de PostgreSQL o `PGPASSWORD`; no se guarda en los scripts.

Desde la raíz del repositorio, en PowerShell:

```powershell
python -m pip install -r requirements.txt
python tpUnidad4/verificar.py --pg-bin 'C:\Program Files\PostgreSQL\17\bin' --port 5432 --user postgres
```

Ajustar `--pg-bin`, `--port` y, si corresponde, `--host`. El verificador crea una **base nueva con nombre único**, con 30 categorías, 600 productos, 20.000 pedidos y 120.000 detalles sintéticos. Instala las restricciones del TP2 y los objetos del TPI. No borra ni modifica bases anteriores. Primero prueba el DDL y la instalación con ROLLBACK; luego confirma. Guarda respaldos en `backups/` (ignorados por Git) y resultados en una subcarpeta nueva de `tpUnidad4/evidencias/`. No hace falta ejecutar de nuevo el laboratorio para publicar los archivos ya verificados.

Las mediciones son cinco ejecuciones con caché caliente, mediana y planes reales; los costos estimados no se interpretan como milisegundos. La carga es sintética. Los tiempos dependen del equipo.

## Instalar sobre una copia ya poblada

No ejecutar `schema.sql` sobre la base que se desea conservar: ese archivo reconstruye las tablas. Hacer primero una copia/restauración de Food Store y un respaldo con `pg_dump`. Sobre esa copia, verificar `SELECT current_database(), current_user;` y ejecutar los dos archivos en este orden. Esta instalación es de una sola vez: si ya existe `unidad4`, falla en lugar de eliminar datos.

```powershell
pg_dump -U postgres -Fc -f backups/food_store_copia_pre_u4.dump food_store_copia
psql -X -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -c 'BEGIN' -f tpUnidad4/tp_fnbc_control_lote.sql -f tpUnidad4/tp_desnormalizacion_top_categorias.sql -c 'ROLLBACK'
# Revisar salida y auditorías vacías; luego confirmar la misma instalación:
psql -X -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -c 'BEGIN' -f tpUnidad4/tp_fnbc_control_lote.sql -f tpUnidad4/tp_desnormalizacion_top_categorias.sql -c 'COMMIT'
```

Los ejecutables deben estar en PATH; ajustar conexión y nombre de base. La auditoría de migración compara la instantánea inicial, por lo que se interpreta justo después de migrar. Las operaciones posteriores se hacen en las dos tablas normalizadas; no se usa la tabla original como segunda fuente editable.

## Sincronización y límites operativos

Una materializada guarda el total por día y categoría. Triggers por sentencia en las cuatro tablas fuente reconstruyen el resumen tras INSERT, UPDATE, DELETE o TRUNCATE dentro de la misma transacción. El resumen se revierte junto con los datos si hay ROLLBACK. No depende de un cron externo y no hay un intervalo programado de datos desactualizados.

Las escrituras se serializan con un advisory lock transaccional antes de modificar las fuentes. Las funciones VOLATILE consultan un snapshot actualizado en READ COMMITTED. Para evitar prometer seguridad con snapshots antiguos, se rechazan explícitamente escrituras en otros niveles de aislamiento. Las lecturas siguen siendo posibles. Este requisito **aplica a la copia con Unidad 4 instalada**, no altera los scripts históricos de concurrencia.

El refresh completo agrega costo a cada sentencia de escritura y puede bloquear lecturas durante su transacción; no es una solución universal para alta tasa de ventas. Conviene agrupar altas por sentencia, mantener transacciones cortas y reintentar la transacción completa si PostgreSQL informa un deadlock. No se deben deshabilitar triggers en operación normal. El dueño de las tablas/superusuario puede hacerlo para las pruebas de auditoría, que siempre se revierten. El usuario de aplicación necesita los permisos de ejecución y actualización de la materializada: no se agregan funciones SECURITY DEFINER ni privilegios implícitos.

La auditoría usa `EXCEPT ALL` en ambos sentidos sobre **todos los días**, e incluye fecha, identificador, nombre e importe; detecta ausencias, sobrantes y cambios. Para consultar:

```sql
SELECT * FROM unidad4.top_categorias_materializado;
SELECT * FROM unidad4.auditoria_ventas; -- cero filas
```

La Parte 1 además preserva `LoteID, DepositoID -> ResponsableControlID` mediante comprobación sobre la reunión: esa dependencia no queda preservada por las claves locales de la descomposición FNBC. Un lock independiente serializa dichas escrituras y se verificó el rechazo de un conflicto concurrente.

## Reversibilidad de la desnormalización

La fuente normalizada nunca se sustituye ni pierde datos. Para retirar **solo** la optimización, sobre una copia y después de respaldar:

```sql
BEGIN;
DROP FUNCTION unidad4.bloquear_ventas() CASCADE; -- elimina sus triggers
DROP FUNCTION unidad4.sincronizar_ventas() CASCADE;
DROP MATERIALIZED VIEW unidad4.ventas_categoria_diaria CASCADE;
-- Se conservan public.*, la fuente y el reporte normalizado, y la Parte 1.
COMMIT;
```

## Uso de IA y fuentes

Se utilizó Codex para revisar el borrador, adaptar SQL, proponer pruebas y redactar documentación. Se aceptó la materialización con sincronización verificada; se descartó el trigger que solo sumaba INSERT, la auditoría unilateral y el uso de columnas inexistentes. No se atribuye uso de otras herramientas no utilizadas. Las evidencias proceden de PostgreSQL, no de tiempos estimados por IA.

- [PostgreSQL: triggers por sentencia](https://www.postgresql.org/docs/17/trigger-definition.html).
- [PostgreSQL: actualización de materializadas](https://www.postgresql.org/docs/17/sql-refreshmaterializedview.html).
- [PostgreSQL: volatilidad y snapshots](https://www.postgresql.org/docs/17/xfunc-volatility.html).
