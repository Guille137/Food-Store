# TP4 — Reportes analíticos sobre Food Store

Continuación del mismo proyecto y la base masiva del TP3. Las cuatro partes están desarrolladas, con planes reales, intentos aceptados y descartados, equivalencia comprobada y DUIA. Se incluyen únicamente entregables y archivos necesarios para reproducirlos.

| Parte | Entregables |
|---|---|
| 1. Optimización de reportes | [Tabla comparativa y joins identificados](informe_optimizacion.md), [spec](spec_analiticas.md), [propuestas](propuestas_ia.md), [índices](indices.sql) |
| 2. Lectura crítica | [Explicación aislada](explicacion_ia.md), [tabla de contraste](lectura_critica.md) |
| 3. Ventana y correlacionada | [Specs](spec_consultas.md), [SQL y pruebas de equivalencia](informe_equivalencia.md) |
| 4. Competencia | [Registro del ranking analítico](registro_competencia.md) |
| Transversal | [DUIA](duia.md) y [ejecutor](laboratorio.py) |

## Consultas finales de la Parte 1

- A1: ejecutar `a1_antes.sql` con los índices de `indices.sql`. Se mantiene la consulta original porque fue más rápida que la reescritura. `a1_despues.sql` es el candidato descartado que se conserva como evidencia del proceso.
- A2: ejecutar `a2_despues.sql` con los índices. La preagregación antes de unir cliente fue la estrategia elegida.

## Reproducción

Requisitos: servidor PostgreSQL 17 local, herramientas pg_dump, usuario con permiso para crear bases, Python 3.10+ y dependencias de `../requirements.txt`. Primero debe existir la base masiva del TP3 con la fase despues completada; no basta con descargar su JSON. No se modifica esa base: el TP4 crea una copia nueva con nombre fechado.

Desde la raíz del repositorio, sustituyendo ruta, puerto y sesión por los de la instancia de laboratorio:

```powershell
python tp4/laboratorio.py antes --sesion tp3/evidencias/20260922_142245/sesion.json --pg-bin 'C:
utaPostgreSQLin'
```

El ejecutor crea la copia, verifica destino y conteos, respalda, actualiza estadísticas y mide ambos reportes. La carpeta nueva de evidencia contiene sesion.json. Después de leer los planes y revisar las propuestas, ejecutar:

```powershell
python tp4/laboratorio.py despues --sesion tp4/evidencias/FECHA/sesion.json --pg-bin 'C:
utaPostgreSQLin'
python tp4/laboratorio.py equivalencia --sesion tp4/evidencias/FECHA/sesion.json --pg-bin 'C:
utaPostgreSQLin'
```

Las opciones --host, --port y --user permiten ajustar la conexión; el puerto predeterminado es 55432. Las contraseñas, si se requieren, se configuran por libpq/pgpass y no se guardan en el repositorio.

Se respalda antes del DDL, se ensayan índices con ROLLBACK y luego se confirman. Las consultas no escriben datos; los fixtures se prueban con ROLLBACK y se comprueba que desaparecen. Las bases y dumps se conservan para inspección, sin eliminación automática. Los respaldos quedan en backups, excluidos de Git.

Las mediciones publicadas corresponden a [evidencias/20260922_151803](evidencias/20260922_151803). Se usa caché caliente, cinco muestras y mediana; los tiempos pueden variar. Los informes describen esta ejecución y no se regeneran automáticamente al repetir el laboratorio. La Parte 4 reutiliza explícitamente el ranking A2 como ejemplo común, sin inventar equipos ni una clasificación externa.
