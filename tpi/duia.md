# Declaración de uso de IA — primera entrega parcial

Herramienta: **Codex**, en la conversación del proyecto, con acceso al repositorio y ejecución local de PostgreSQL. No se declara uso de Kiro/OpenCode ni un modelo específico que no se haya identificado.

## Solicitud y especificación utilizadas

Solicitud del alumno:

> Ok, entonces hazlo... Deja todo organizado en Github para que sea facil de entender para el docente...

Contexto: condiciones completas de la primera entrega parcial, con nueve objetivos y un informe técnico de cinco puntos; trabajos anteriores, esquema real y `AGENTS.md`. La [especificación previa](spec_objetos.md), conservada en el commit `5c9b834`, fue el contexto para generar los nuevos objetos y las pruebas. No se inventan prompts a herramientas que no se utilizaron.

## Intervenciones y decisiones

| Propósito y contexto | Propuesta / trabajo de Codex | Decisión técnica y comprobación |
|---|---|---|
| Nueve objetivos contra archivos existentes | Mapa de cobertura y faltantes | Conservar TP2–TP5; completar modelo/normalización, procedimientos y resumen |
| Modelo y DDL existente | ER, participación y paso a relaciones | Cliente–Pedido 1:N; DetallePedido resuelve N:M; no inventar mínimos que el SQL no impone |
| Dependencias y claves del dominio | Justificación 1FN/2FN/3FN/BCNF | Claves alternativas UNIQUE NOT NULL; producto no determina precio histórico |
| Función de spec_objetos.md | tpi_total_pedido | Aceptada: 45 en pedido de dos líneas, 0 en vacío, P0002 en inexistente; conserva historia |
| Alta de spec_objetos.md | JSONB validado, salida INOUT y precio bajo FOR SHARE | Aceptado: error posterior no deja cabecera ni detalle; sin COMMIT interno |
| Baja de spec_objetos.md | UPDATE activo=false | Aceptado; descartar DELETE y reutilización de nombres: conservar FK, UNIQUE e historia |
| Tablas de transición de spec_objetos.md | Validación por sentencia de categorías | Regla nueva del TPI, con INSERT/UPDATE múltiples y concurrencia probados |
| Reproducción independiente | Instalar todos los objetos en una base vacía nueva | Aceptado; no exigir bases privadas anteriores. Respaldos y ensayo reversible |
| Presentación para el docente | README central, mapa de objetivos e informe breve | Enlazar pruebas existentes, sin duplicar benchmarks ni agregar guías personales |

Los scripts y documentos se elaboraron con asistencia de Codex. La revisión técnica contrastó propuestas con el modelo real y las salidas del motor; no se presentan afirmaciones de autoría sin asistencia. Las mediciones previas se citan con sus sesiones originales.

## Verificación y límites

PostgreSQL 17.11 completó 79 comprobaciones, incluido el ensayo DDL. Se guardaron sentencias, parámetros, resultados, SQLSTATE esperados y planes de baja lógica. La concurrencia usó conexiones reales y `pg_blocking_pids`. El JSON de evidencia marca `exito: true`.

No se añadió total redundante ni descuento automático de stock que cambiara la regla heredada. No se crearon columnas de contraseña para imitar otro esquema. Las tablas de transición validan categorías de las nuevas versiones de detalles; no eliminan historia al desactivar categorías.

Las decisiones de rendimiento, incluidos descartes, siguen en [TP3](../tp3/duia.md), [TP4](../tp4/duia.md) y [TP5](../tp5/duia.md). No se afirma que se repitieron todos los benchmarks en la base pequeña del TPI.

## Historial de incorporación

| Commit | Contenido |
|---|---|
| 5c9b834 | Especificación previa |
| de699a4 | Función de total histórico |
| 8b09ebe | Alta atómica desde JSONB |
| 144d4f6 | Baja lógica |
| 772e9e1 | Tablas de transición |
| 4548798 | Modelo ER, paso relacional y BCNF |

Los commits siguientes incorporan ejecutor/evidencia y organización de entrega. No se reescribe el historial previo.

