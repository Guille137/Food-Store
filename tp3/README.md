# TP3 — Optimización de consultas sobre Food Store

Las Partes 1 a 4 están desarrolladas y verificadas sobre el mismo proyecto Food Store de los TP anteriores. Se usan schema.sql, datos_iniciales.sql y las restricciones del TP2, documentando su correspondencia con los nombres de referencia del PDF. La Parte 5 queda pendiente de la consulta y las condiciones oficiales de la competencia.

## Resolución

| Parte | Documentación y archivos |
|---|---|
| 1. Carga masiva | [Especificación](spec_carga.md), [script](carga_masiva.sql), [controles y protocolo](informe_carga.md) |
| 2. Optimización | [Tabla comparativa y planes](informe_optimizacion.md), [propuestas de IA](propuestas_ia.md), [índices](indices.sql), [consultas finales](consultas_optimizadas.sql) |
| 3. Lectura crítica | [Explicación aislada](explicacion_ia_plan.md), [tabla de contraste](lectura_critica_plan.md) |
| 4. Equivalencia | [Especificaciones](spec_consultas.md), [consultas y resultados](informe_equivalencia.md), [verificación SQL](verificar_equivalencia.sql) |
| 5. Competencia | [Estado y material requerido](registro_competencia.md) |
| Transversal | [DUIA completa de lo realizado](duia.md), [guía de defensa](guia_defensa.md) |

## Reproducción

Requisitos: PostgreSQL 17 con herramientas pg_dump y un usuario que pueda crear bases de laboratorio, Python 3.10+ y las dependencias de `../requirements.txt`. El servidor debe estar iniciado; el ejecutor no lo instala ni lo arranca. Usa variables habituales de libpq para autenticación, sin guardar contraseñas en el código.

Desde la raíz del repositorio, con PostgreSQL local en el puerto 55432:

```powershell
python tp3/laboratorio.py antes --pg-bin 'C:\ruta\PostgreSQL\bin'
```

Se crean una plantilla, un ensayo revertido y una copia de trabajo nueva. Se cargan 50.000 productos, 20.000 clientes, 200.000 pedidos y 600.000 detalles; se ejecuta VACUUM (ANALYZE) y se guardan cinco planes por consulta antes de crear índices. El ejecutor imprime la ruta del archivo sesion.json, que se usa en las fases siguientes.

Después de revisar los planes y propuestas, reemplazar FECHA por la carpeta generada:

```powershell
python tp3/laboratorio.py despues --sesion tp3/evidencias/FECHA/sesion.json --pg-bin 'C:\ruta\PostgreSQL\bin'
python tp3/laboratorio.py equivalencia --sesion tp3/evidencias/FECHA/sesion.json --pg-bin 'C:\ruta\PostgreSQL\bin'
```

Se pueden ajustar `--host`, `--port` y `--user`. No se eliminan bases ni respaldos automáticamente. No ejecutar carga_masiva.sql dos veces sobre la misma base: para repetir el laboratorio se crea una sesión nueva. La opción `antes --sesion ...` permite reanudar solamente una preparación interrumpida propia cuyos conteos se comprueban; no vuelve a insertar datos.

Las mediciones de esta entrega están en [evidencias/20260922_142245](evidencias/20260922_142245). Las futuras ejecuciones producirán tiempos y estadísticas diferentes. Los informes describen la ejecución registrada; no se regeneran automáticamente con cada ensayo.
