# Declaración de uso de IA — TP5

Herramienta utilizada: **Codex**, en esta conversación y con terminal/SQL sobre PostgreSQL local. Se usó para especificar, generar SQL y Python, revisar, ejecutar y redactar informes. No hubo uso de Kiro ni OpenCode; no se inventan sesiones, prompts externos ni un identificador de modelo. La elección se apoya en la aclaración previa del alumno: «en cuanto al uso de la IA se podia usar la que prefirieramos». Se mantiene la secuencia especificar → generar → revisar → probar → versionar.

## Solicitud y contexto efectivamente utilizados

Solicitud de esta etapa, literal:

> Continuamos con la resolucion del tp5 y posterior haremos el parcial cuando termines

Contexto aportado: `BD2_TP_Unidad3_Semana1_Indices_Vistas.pdf`, esquema y restricciones del repositorio, carga masiva e índices de TP3/TP4, y las instrucciones de conservar el mismo Food Store, hacer commits descriptivos por corrección/objeto y publicar únicamente entregables. Se leyó también `AGENTS.md` y se aplicaron copias fechadas, respaldos y ensayos revertidos.

Las especificaciones completas utilizadas como contexto de generación están versionadas en [specs/indices.md](specs/indices.md), [specs/vistas.md](specs/vistas.md) y [specs/materializada.md](specs/materializada.md). Las consultas exactas de indexado están en [queries.sql](queries.sql). Son los textos efectivos, no reconstrucciones abreviadas de un supuesto prompt a otra herramienta. Codex las redactó en esta misma sesión y después generó los objetos a partir de ellas. El commit `e344795` conserva esas especificaciones **antes** del primer CREATE INDEX/VIEW.

## Intervenciones relevantes y decisiones

| Etapa/contexto exacto | Propuesta de Codex | Resolución y fundamento |
|---|---|---|
| Preparación: PDF, AGENTS y esquema anterior | Reutilizar la base masiva del TP4 mediante copias nuevas | Aceptado. Se conservaron tablas, restricciones, triggers e índices previos. Dos copias comparables para escritura; no se utilizó una base productiva. |
| I1 de specs/indices.md y Q1 | B-tree de lower(nombre), parcial por activo | Aceptado tras ensayo y comparación: Seq Scan → Bitmap; 9,870 → 0,024 ms. No confundir con el UNIQUE de nombre. |
| I2 de specs/indices.md y Q2 | Parcial por confirmado/tarjeta, orden fecha/id y columnas INCLUDE | Aceptado: mantiene resultados y orden; 19,342 → 2,776 ms. El índice de entregados no sirve para esta cola. |
| I3 de specs/indices.md y Q3 | B-tree por precio histórico, pedido y producto; INCLUDE cantidad | Aceptado con costo explícito: 58,102 → 0,311 ms; ocupa unos 23,2 MiB y aumenta escritura/WAL. |
| Revisión de sobreindexación de specs/indices.md | Índice adicional de detalle por id_pedido | **Descartado sin crear**: la PK y el índice cubierto del TP4 ya empiezan por esa clave. Para la carga elegida no aporta un acceso diferente. |
| Escritura de specs/indices.md | Comparar 800 filas con/sin índices | Se precisó el ensayo con 800 INSERT individuales y además un INSERT SELECT de 800 filas. Siete pares alternados, ROLLBACK y control de conteos; se reportan ambos métodos sin confundir tiempo cliente con servidor. |
| V1 de specs/vistas.md | Vista de productos y categorías activos | Aceptada tras cero diferencias bidireccionales y prueba de baja de producto/categoría. 45.002 filas normales. |
| V2 de specs/vistas.md | Vista de pedidos y datos públicos del cliente | Adaptado al esquema: no hay usuario/contraseña; se excluyen email/teléfono, sin inventar columnas. Lectura con rol limitado permitida y acceso a tablas rechazado. |
| V3 de specs/vistas.md | Vista del detalle con producto y subtotal | Aceptada sin filtrar activo ni estado para conservar historia. 600.000 filas iguales a referencia; bajas, cancelados y precio de venta diferente al actual verificados. |
| specs/materializada.md y A1 del TP4 | Agregado mensual por categoría WITH DATA | Aceptado: mismo resultado, 39 filas; 217,223 → 0,024 ms de lectura. Mantiene semántica de catálogo vigente. |
| Índice único de specs/materializada.md | UNIQUE por categoría/mes sin WHERE ni expresión | Aceptado y versionado aparte. REFRESH CONCURRENTLY ejecutado; prueba de venta nueva y restauración tras ROLLBACK. |
| Informe, evidencias y README | Informar resultados observados y política de refresco | Aceptado con límites: frecuencias supuestas, caché caliente, variabilidad, sin prometer mejora universal ni afirmar que se instaló un programador. |

## Revisión del SQL y validación

Antes de ejecutar cada objeto se revisaron columnas reales, predicados, claves, JOIN, precisión de importes y permisos. No hay ALTER TABLE ni cambio de restricciones. Todos los CREATE se ensayaron primero con ROLLBACK y respaldo previo; solo luego se aplicaron a la copia. Las pruebas de error usaron SAVEPOINT. La revisión automatizada de definiciones de columnas, restricciones y triggers confirmó que el modelo permaneció igual.

Las consultas de contraste de la Parte B, en [referencias_vistas.sql](referencias_vistas.sql), fueron redactadas con asistencia de Codex. Consultan directamente las tablas base mediante CTE y subconsulta escalar, sin reutilizar las vistas que se verifican. Para **las tres vistas**, EXCEPT ALL en ambos sentidos devolvió cero y coincidieron todas las filas ordenadas; se repitió con bordes. Estas consultas y sus resultados forman parte de la solución entregada.

En la revisión final solicitada por el alumno se comprobó que las tres consultas ya estaban implementadas y verificadas. Se aclaró su condición de solución final en el README y el informe, conservando el SQL probado y esta declaración de asistencia. No fue necesario modificar las consultas ni repetir mediciones por cambios de documentación.

Las mediciones provienen de PostgreSQL, no de estimaciones de IA. El [informe](informe_mediciones.md), los [planes](evidencias/20260922_194616) y [laboratorio.py](laboratorio.py) permiten comprobarlo. Los errores 42501 y 42703 de seguridad fueron esperados y controlados, no fallas sin resolver. No se agregaron guías personales de defensa al repositorio.

## Historial de objetos

| Commit | Pieza |
|---|---|
| e344795 | Especificaciones previas y consultas exactas |
| 7ae0fd9 | I1, búsqueda por nombre de producto |
| b5430ca | I2, cola confirmada con tarjeta |
| 918075d | I3, precio histórico de detalle |
| c0ab013 | V1, productos vigentes |
| 84bce7f | V2, pedidos/clientes sin contacto |
| f480b4f | V3, detalle histórico |
| baf095c | Vista materializada WITH DATA |
| 4b37c00 | Índice único y prueba de refresco concurrente |

Los commits posteriores reúnen las verificaciones finales, la documentación y el ejecutor; no reescriben el historial de las piezas.
