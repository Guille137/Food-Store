# Parte 5 — Competencia de optimización

Se desarrolla el ejemplo indicado en la consigna, conforme a la aclaración del alumno: listado de productos por categoría con filtro de precio y orden, inicialmente sin un índice aplicable. Se continúa el mismo proyecto Food Store.

## Consulta y parámetros

Archivo: [competencia.sql](competencia.sql). Categoría 1, precio entre 1000 y 1500 inclusive, productos activos, orden por precio ascendente e id ascendente como desempate y LIMIT 50. Estos parámetros concretan el ejemplo de la guía; las tres estrategias ejecutan exactamente el mismo SQL.

## Preparación y medición

Se creó `food_store_tp3_competencia_20260922_144517` copiando la base masiva del TP3. Solo en esa copia se retiraron idx_producto_categoria y tp3_producto_categoria_precio para obtener el punto de partida sin índice aplicable a los filtros. Se conservaron la PK y el UNIQUE del nombre, que no sustituyen esos accesos; no se eliminaron restricciones ni se forzó Seq Scan.

Antes de cada cambio estructural se guardó un dump en backups y se ejecutó primero con BEGIN/ROLLBACK y luego con BEGIN/COMMIT. Se actualizó el mantenimiento de producto con VACUUM (ANALYZE). Cada estrategia tuvo un calentamiento y cinco ejecuciones EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON); se compara la mediana de Execution Time. Cada plan TXT corresponde a una ejecución adicional de diagnóstico y su tiempo puede diferir de la mediana.

## Registro de la competencia

| Equipo / entrega | Estrategia aplicada | Tiempo antes (ms) | Tiempo después (ms) | Mejora (x) |
|---|---|---:|---:|---:|
| Guille137 / Food-Store | Índice compuesto parcial por categoría, precio e id, con nombre incluido | 10,993 | 0,039 | 281,87 |

Se registra la estrategia de esta entrega. No se atribuyen tiempos a otros equipos ni se declara un ganador entre equipos sin esos datos.

## Estrategias ensayadas y decisión

| Estrategia | Mediana (ms) | Plan observado | Decisión |
|---|---:|---|---|
| Sin índice aplicable | 10,993 | Seq Scan y Sort top-N; 48.331 filas descartadas por filtro | Línea base |
| Índice simple por categoria_id | 4,555 | Bitmap Index Scan, Bitmap Heap Scan y Sort; 14.996 filas descartadas por filtro | Mejora respecto a la base, pero se descarta como solución final frente al compuesto |
| Índice parcial compuesto | 0,039 | Index Only Scan y Limit; sin Sort explícito | Se acepta por menor mediana y resultados equivalentes |

Índice elegido:

```sql
CREATE INDEX tp3_comp_compuesto
ON producto(categoria_id, precio_lista, id_producto)
INCLUDE(nombre) WHERE activo=TRUE;
```

La igualdad de categoría y el rango de precio quedan en Index Cond; el orden del índice permite detenerse tras las 50 filas. El plan final informa 6 shared hits y Heap Fetches=1: no se afirma que el acceso evitara absolutamente toda visita a la tabla. Los tres resultados se compararon como listas completas y devolvieron las mismas 50 filas en el mismo orden.

La elección se basa en tiempo real, no en costo estimado. Los factores corresponden a esta carga y caché caliente; los tiempos muy pequeños son sensibles a variación y no garantizan esa mejora en otro entorno. El índice consume espacio y mantenimiento en escrituras. No se ocultó el candidato simple: queda medido aunque no fue seleccionado.

## Evidencia y reproducción

- [Planes y cinco mediciones por estrategia](evidencias/competencia_20260922_144517/resultados.json).
- [Plan sin índice](evidencias/competencia_20260922_144517/sin_indice.txt).
- [Plan con índice simple](evidencias/competencia_20260922_144517/categoria_simple.txt).
- [Plan elegido](evidencias/competencia_20260922_144517/compuesto_parcial.txt).
- [Ejecutor](competencia.py), con creación de copia nueva, respaldo, transacciones, comparación y selección de la menor mediana.

Desde la raíz, con PostgreSQL iniciado y las dependencias instaladas:

```powershell
python tp3/competencia.py --sesion tp3/evidencias/20260922_142245/sesion.json --pg-bin 'C:\ruta\PostgreSQL\bin'
```

La base fuente debe existir en la instancia local; si se reproduce desde cero, primero se ejecutan las fases antes/despues del laboratorio y se indica su nuevo archivo sesion.json. Cada ejecución crea una copia y una carpeta de evidencia nuevas.
