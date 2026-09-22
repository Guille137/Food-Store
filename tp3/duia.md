# Declaración de Uso de IA — TP3

Herramienta utilizada: Codex de OpenAI, asistente basado en GPT-6 según la identificación de esta sesión. No se expone un identificador de snapshot más específico. El alumno aclaró que podía elegir la herramienta de IA; no se atribuye el trabajo a OpenCode ni Kiro.

| Uso | Prompt / especificación | Resultado aceptado o descartado y motivo | Verificación |
|---|---|---|---|
| Interpretación y adaptación | Resolver el TP3 sobre Food Store y pedir al alumno solo acciones no ejecutables por el asistente. | Se continúa el mismo proyecto: usuarios corresponde a cliente y vigencia a activo. Se documenta la correspondencia entre los nombres de archivos del PDF y los del repositorio. | Inspección de PDF y esquema existente. |
| Carga masiva | [Spec previa](spec_carga.md): 50.000 productos, 20.000 clientes, 200.000 pedidos y tres detalles por pedido; restricciones activas. | Se acepta generate_series determinista, claves recuperadas por RETURNING y pedidos pendientes antes de insertar detalles. | Ensayo completo con ROLLBACK, carga en otra copia con COMMIT, conteos y controles reales. |
| Optimización de Q1–Q3 | Analizar los planes reales guardados y proponer índices o reescrituras que ataquen sus nodos sin cambiar resultados ni forzar el optimizador. | Se aceptan los tres candidatos tras medir mejoras. Se descartan duplicar el índice de categoría, indexar solo activo y forzar enable_seqscan. Razones en [propuestas](propuestas_ia.md). | Cinco medidas antes/después, planes completos y comparación bidireccional con EXCEPT ALL. |
| Ejecutor de mediciones | Separar preparación y fase posterior para leer los planes antes de escribir índices; conservar todas las mediciones. | Se corrigió un lector que separaba por un punto y coma de un comentario. Se reanudaron las mediciones sin repetir la carga. | La ejecución completa posterior produjo los tres pares de planes y comprobó los conteos. |
| Explicación aislada de un plan | Explicar solo el texto del plan Q1 final, nodo por nodo, sin herramientas ni contexto adicional. [Prompt y respuesta literal](explicacion_ia_plan.md). | Segundo agente autorizado por el alumno, sin historial compartido. Se conserva íntegramente su respuesta. | [Tabla crítica](lectura_critica_plan.md) con nueve afirmaciones contrastadas. |
| Consultas de resumen y subconsulta | [Specs previas](spec_consultas.md): filtros de vigencia, columnas, orden y tratamiento de ausencia de ventas. | Primera versión generada sin solución previa; después se pidió una alternativa con distinta estructura. Ambas versiones tienen asistencia de IA. | EXCEPT ALL en ambas direcciones, listas ordenadas completas y casos límite con resultados esperados. |
| Informes y defensa | Documentar resultados observados, limitaciones, decisiones e instrucciones de reproducción. | Se conservan tiempos reales, limitaciones de caché y costo de índices. Se preparó una guía de estudio. | Los informes enlazan a las evidencias de PostgreSQL; no se declara una defensa oral realizada. |

## Parte 5 — Ejemplo de la competencia

Indicación exacta del alumno: «Hay que usar eso de ejemplo». Se concretó el listado por categoría con categoría 1, precio entre 1000 y 1500, activos y orden precio/id, LIMIT 50. Codex preparó competencia.sql y competencia.py para crear una copia nueva, medir sin índice aplicable y comparar un índice simple con un compuesto parcial.

Se aceptó el compuesto tras observar medianas de 10,993 ms sin índice, 4,555 ms con índice simple y 0,039 ms con compuesto parcial. Se descartó el simple como estrategia final aunque mejoró la base; su evidencia se conserva. Las 50 filas y su orden coincidieron en las tres estrategias. Se registraron dumps previos, ensayos ROLLBACK y planes completos en [registro_competencia.md](registro_competencia.md). No se inventaron resultados de otros equipos ni una clasificación general.

La revisión asistida y las pruebas automáticas no reemplazan la lectura personal ni la capacidad del alumno de explicar cada script en la defensa.
