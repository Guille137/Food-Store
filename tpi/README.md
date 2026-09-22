# Parcial 1 - TPI — Food Store

**Grupo: Octavio Skumanic, Sebastián Vivanco, Victoria Guzman, Daniela Sosa, Guillermo Sanchez**

**Materia:** Base de Datos II. **Alcance:** unidades 1, 2 y 3. **Motor utilizado:** PostgreSQL 17.11, compatible con el mínimo 16+ solicitado.

La entrega reúne el modelo, scripts SQL, objetos PL/pgSQL y evidencia de ejecución. Se reutilizan los TP anteriores y se agregan los objetos que faltaban para esta instancia. La documentación del modelo corresponde a las tablas efectivamente implementadas.

## Recorrido de evaluación

1. Leer el [informe técnico](informe_tecnico.md): implementación por unidad, resultados y optimizaciones.
2. Consultar la siguiente matriz para localizar cada requisito.
3. Revisar el [resumen de pruebas](resultados.md) y, si se necesita el detalle, el [registro SQL completo](evidencias/20260922_204000_480700/resultado.json).
4. Para reproducir sin bases anteriores, ejecutar el comando de instalación y verificación que aparece más abajo.

## Matriz de los nueve objetivos

| N.º | Objetivo exigido | Implementación / documentación | Evidencia |
|---|---|---|---|
| 1 | ER: entidades, atributos, claves, cardinalidad y participación | [Modelo, diagrama y diccionario](modelo.md) | Correspondencia explícita con [schema.sql](../schema.sql) |
| 2 | Paso al modelo relacional, 1:N y N:M | [Transformación y tabla asociativa](modelo.md#paso-al-modelo-relacional) | PK/FK de las cinco tablas y pruebas de integridad |
| 3 | 3FN/BCNF y dependencias funcionales | [Justificación por relación](normalizacion.md) | Claves candidatas y dependencias contrastadas con PK/UNIQUE/NOT NULL |
| 4 | DDL, tipos, PK/FK, restricciones e índices | [Esquema](../schema.sql), índices [TP3](../tp3/indices.sql), [TP4](../tp4/indices.sql), [TP5](../tp5/indices.sql) | Instalación desde cero y pruebas CHECK/UNIQUE/FK en [resultados](resultados.md) |
| 5 | DML, JOIN, agregación, subconsultas, GROUP BY/HAVING, ventanas | [Mapa de consultas y escrituras](consultas.md) | [Equivalencia TP4](../tp4/informe_equivalencia.md) y llamadas/transacciones del TPI |
| 6 | Vistas, funciones y procedimientos PL/pgSQL | [Vistas](../tp5/views.sql), [materializada](../tp5/materializadas.sql), [función](funciones.sql), [alta con CALL](registrar_pedido.sql), [baja con CALL](baja_producto.sql) | Totales, dos procedimientos, JSONB, equivalencia de tres vistas y REFRESH comprobados |
| 7 | CHECK, UNIQUE y triggers | [Reglas anteriores](../restricciones_Food_Store.sql), [tablas de transición](categorias_transicion.sql) | SQLSTATE esperados y operaciones de varias filas [probadas](resultados.md) |
| 8 | Atomicidad, COMMIT/ROLLBACK, aislamiento y concurrencia | [Informe de dos sesiones TP2](../informe_concurrencia.md), [ejecutor TPI](verificar_tpi.py) | READ COMMITTED/REPEATABLE READ previos; reversión de CALL, visibilidad y bloqueo real nuevos |
| 9 | Borrado lógico e impacto en consultas/índices | [Procedimiento de baja](baja_producto.sql), [reglas de vigencia](resultados.md#borrado-lógico) | Historial conservado; venta nueva rechazada; índice parcial devuelve una fila antes y cero después |

## Reproducción desde cero

Requisitos: PostgreSQL 16+ local iniciado, herramientas `pg_dump`, Python 3.10+ y un usuario de laboratorio con permiso para crear bases y objetos. La sesión registrada utilizó PostgreSQL 17.11 con usuario postgres. **No hace falta disponer de las bases locales de TP2–TP5.**

Desde la raíz del repositorio, en PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe tpi/verificar_tpi.py --pg-bin 'C:/ruta/PostgreSQL/17/bin' --host 127.0.0.1 --port 55432 --user postgres
```

Sustituir ruta, puerto y usuario por los de la instalación local. Si se requiere contraseña, usar libpq/pgpass; no incluirla en el repositorio. El script no instala ni inicia el servidor.

El ejecutor crea `food_store_tpi_FECHA_HORA_MICROSEGUNDOS`, comprueba la conexión y nunca sobreescribe una base existente. Instala el esquema, seed, restricciones, índices y vistas anteriores, y los nuevos objetos del TPI. Guarda respaldos antes del DDL en `backups/` (excluidos de Git), ensaya con ROLLBACK y después aplica lo verificado. Agrega 4.000 productos sintéticos para observar el índice parcial sin desactivar Seq Scan. Es una prueba funcional; los benchmarks de 600.000 detalles se conservan en TP3–TP5.

Se prueban casos correctos e incorrectos, las dos clases de trigger con tabla de transición, el manejo de JSONB, COMMIT/ROLLBACK y dos conexiones concurrentes. Los casos negativos usan SAVEPOINT; los casos de borde se revierten. Se conserva un pedido de prueba confirmado mediante COMMIT y luego entregado, además de sus productos/categorías, para comprobar persistencia y refresco.

Salida registrada: **`TPI VERIFICADO: 79 comprobaciones`**. Cada ejecución escribe su propia carpeta `tpi/evidencias/FECHA/resultado.json`, con `exito: true` al completar todo. Si falla, conserva el error con `exito: false` y termina con código de error. No se borran bases ni dumps automáticamente. Los informes describen la sesión publicada, no se regeneran al repetir el ejecutor.

## Orden de los scripts

El ejecutor realiza este orden; no es necesario ejecutar cada archivo manualmente:

1. `schema.sql`, `restricciones_Food_Store.sql`, `datos_iniciales.sql`.
2. `tp3/indices.sql`, `tp4/indices.sql`, `tp5/indices.sql`.
3. `tp5/views.sql`, `tp5/materializadas.sql`.
4. `tpi/funciones.sql`, `tpi/registrar_pedido.sql`, `tpi/baja_producto.sql`, `tpi/categorias_transicion.sql`.

`schema.sql` elimina tablas si existen: por eso solo se ejecuta sobre la base **nueva** creada por el verificador. Los CREATE de esta entrega se aplican una vez; para repetir, iniciar otra ejecución completa. No ejecutar el instalador sobre producción.

La regla de categoría activa en nuevas líneas/ediciones se agrega en el TPI; los informes de TP2–TP5 conservan sus resultados históricos y versiones. Las bajas no eliminan ventas previas. Los objetos son SECURITY INVOKER: no conceden al llamador permisos que no tenía sobre las tablas.

## Documentación complementaria de la entrega

- [Especificación previa de los nuevos objetos](spec_objetos.md).
- [Declaración de uso de IA y decisiones](duia.md).
- Antecedentes conservados: [TP2](../README_TP2.md), [TP3](../tp3/README.md), [TP4](../tp4/README.md), [TP5](../tp5/README.md).

No se incluyen guías personales de defensa ni material ajeno a los requisitos y su verificación.
