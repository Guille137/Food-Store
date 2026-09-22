# TP5 — Índices y vistas de Food Store

Continuación del mismo repositorio y la base masiva de TP3/TP4. Contiene tres índices medidos, tres vistas verificadas y una vista materializada con refresco concurrente. Se conservan las tablas y restricciones. Las mediciones registradas corresponden a PostgreSQL 17.11 del 22/09/2026.

| Entregable | Archivo |
|---|---|
| Especificaciones anteriores a la generación | [specs/](specs/) |
| Carga de consultas para indexar | [queries.sql](queries.sql) |
| Índices aceptados | [indices.sql](indices.sql) |
| Vistas de reportes y seguridad | [views.sql](views.sql) |
| Referencias de equivalencia | [referencias_vistas.sql](referencias_vistas.sql) |
| Materializada e índice único | [materializadas.sql](materializadas.sql) |
| Agregación original | [reporte_original.sql](reporte_original.sql) |
| Planes, tiempos de lectura/escritura, descarte y verificaciones | [informe_mediciones.md](informe_mediciones.md) |
| Declaración de uso de IA e historial por objeto | [duia.md](duia.md) |
| Reproducción y evidencia de ejecución | [laboratorio.py](laboratorio.py), [evidencias/20260922_194616](evidencias/20260922_194616) |

## Correspondencia con la estructura de la guía

Los nuevos archivos están en `tp5/` para conservar las entregas anteriores. El `schema.sql` heredado sigue en [la raíz](../schema.sql), sin cambios. Los datos están en [datos_iniciales.sql](../datos_iniciales.sql) y [tp3/carga_masiva.sql](../tp3/carga_masiva.sql), equivalentes al `data.sql` de referencia. Las consultas previas permanecen en [tp3/consultas_lentas.sql](../tp3/consultas_lentas.sql), [tp3/consultas_optimizadas.sql](../tp3/consultas_optimizadas.sql) y [tp4/](../tp4/); `tp5/queries.sql` amplía esa carga con filtros todavía no indexados.

Nuestro esquema usa `cliente` en vez de `usuario` y no contiene contraseñas. La vista de seguridad oculta los datos de contacto existentes y se prueba con un rol sin acceso a las tablas. No se agrega una columna de contraseña para simular el ejemplo. Se empleó Codex conforme a la libertad de herramienta comunicada por el alumno, declarando el uso real. La Parte B incluye las tres consultas de contraste y la comprobación de equivalencia, tanto sobre la base masiva como con casos límite.

## Reproducir

Requisitos: PostgreSQL 17 local iniciado, sus herramientas `pg_dump`, Python 3.10+ y `pip install -r requirements.txt`. Usuario de laboratorio con permiso para crear bases y roles de prueba y cambiar al rol creado; la ejecución registrada usó postgres en una instancia aislada. Autenticación mediante libpq/pgpass si corresponde; no guardar credenciales en Git. Predeterminados: host 127.0.0.1, puerto 55432, usuario postgres; las opciones `--host`, `--port`, `--user` los cambian.

**Debe existir la base del TP4 con sus índices aplicados.** Descargar un archivo sesion.json no crea esa base. En una instalación nueva, seguir primero [TP3](../tp3/README.md) (`antes`, `despues`) y luego [TP4](../tp4/README.md) (`antes`, `despues`), usando las nuevas sesiones impresas por los ejecutores. La fuente registrada en esta entrega fue `food_store_tp4_20260922_151803`.

Desde la raíz del repositorio, en PowerShell, sustituir ruta y FECHA_TP4 por los valores locales:

```powershell
$binPgTp5 = 'C:/ruta/PostgreSQL/17/bin'
python tp5/laboratorio.py preparar --sesion tp4/evidencias/FECHA_TP4/sesion.json --pg-bin $binPgTp5
```

La preparación crea copias nuevas con nombre fechado, comprueba conexión y conteos, respalda, crea el pedido vacío para escritura y ejecuta VACUUM ANALYZE. No sobreescribe bases. Imprime la ruta de **una nueva sesión del TP5**. Usarla a continuación, sin modificar la evidencia histórica publicada:

```powershell
$sesionTp5 = 'tp5/evidencias/FECHA_NUEVA/sesion.json'
python tp5/laboratorio.py indice --numero 1 --sesion $sesionTp5 --pg-bin $binPgTp5
python tp5/laboratorio.py indice --numero 2 --sesion $sesionTp5 --pg-bin $binPgTp5
python tp5/laboratorio.py indice --numero 3 --sesion $sesionTp5 --pg-bin $binPgTp5
python tp5/laboratorio.py escritura --sesion $sesionTp5 --pg-bin $binPgTp5
python tp5/laboratorio.py vista --numero 1 --sesion $sesionTp5 --pg-bin $binPgTp5
python tp5/laboratorio.py vista --numero 2 --sesion $sesionTp5 --pg-bin $binPgTp5
python tp5/laboratorio.py vista --numero 3 --sesion $sesionTp5 --pg-bin $binPgTp5
python tp5/laboratorio.py materializada --sesion $sesionTp5 --pg-bin $binPgTp5
python tp5/laboratorio.py unico --sesion $sesionTp5 --pg-bin $binPgTp5
python tp5/laboratorio.py verificar --sesion $sesionTp5 --pg-bin $binPgTp5
```

Ejecutar en ese orden y detenerse ante un error. Cada fase de creación procesa solo el objeto indicado, ensaya con ROLLBACK y después aplica tras comprobar resultados. No ejecutar además los SQL por separado sobre la misma copia: duplicaría objetos. Para repetir toda la práctica, comenzar con `preparar` y una sesión nueva. Los dumps quedan en `backups/`, excluidos de Git, y las bases se conservan para inspección.

La fase `escritura` hace siete pares de cargas de 800 filas, en ambas variantes, y revierte cada una. La fase `verificar` comprueba las tres vistas, errores esperados de permisos con SAVEPOINT, bajas/cancelaciones, precio histórico, pedido vacío, desactualización y refresco de la MV. Revierte todos los casos y los GRANT/rol, y confirma que no cambiaron tablas, restricciones ni triggers. Los avances de secuencias no se revierten; las filas de prueba sí.

Resultado esperado: sesión con `estado: verificado`, `modelo_sin_cambios: true`, `bordes_y_permisos_revertidos: true`, diferencias de equivalencia cero y salida final `Modelo base, restricciones y triggers sin cambios`. Los tiempos pueden variar; el informe publicado describe la sesión registrada y no se regenera automáticamente.

## Consultar y refrescar

```sql
SELECT * FROM tp5_productos_vigentes ORDER BY id_producto;
SELECT * FROM tp5_pedidos_clientes WHERE id_cliente = 1 ORDER BY id_pedido;
SELECT * FROM tp5_detalles_productos WHERE id_pedido = 4 ORDER BY id_producto;
SELECT * FROM tp5_facturacion_mensual ORDER BY mes, id_categoria;
REFRESH MATERIALIZED VIEW CONCURRENTLY tp5_facturacion_mensual;
```

Las vistas comunes leen el estado visible en la transacción; la materializada conserva el último refresco. La política propuesta es cada 15 minutos y después del cierre mensual. No se instala una tarea programada; el informe explica su costo y la demora de actualización. La vista de permisos es una proyección global de reportes, no aislamiento de clientes.

El repositorio incluye únicamente entregables y archivos necesarios para verificarlos. El enlace de entrega sigue siendo [Food-Store](https://github.com/Guille137/Food-Store), con acceso directo a [tp5](https://github.com/Guille137/Food-Store/tree/main/tp5).
