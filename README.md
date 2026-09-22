# Food Store — Base de Datos II

**Guillermo Sánchez · Primera entrega parcial del Trabajo Práctico Integrador · Unidades 1, 2 y 3**

Proyecto implementado y probado en **PostgreSQL 17.11** (mínimo requerido: 16+). Incluye el modelo, SQL, objetos PL/pgSQL, documentación y evidencia de ejecución. El desarrollo continuará en las unidades siguientes.

## Entrada para la evaluación

| Documento | Contenido |
|---|---|
| **[Entrega integradora y mapa de los nueve objetivos](tpi/README.md)** | Cada requisito con enlaces a implementación, pruebas y reproducción |
| **[Informe técnico](tpi/informe_tecnico.md)** | Implementación por unidad, resultados, optimizaciones antes/después y uso de IA |
| [Modelo ER y paso al modelo relacional](tpi/modelo.md) | Diagrama, atributos, claves, cardinalidades, participación y diccionario |
| [Normalización hasta BCNF](tpi/normalizacion.md) | Dependencias funcionales y justificación por tabla |
| [Resultados del integrador](tpi/resultados.md) | 79 comprobaciones reales: objetos, atomicidad, bajas, concurrencia y vistas |
| [Declaración de uso de IA](tpi/duia.md) | Herramienta utilizada, especificaciones y decisiones aceptadas/descartadas |

## Qué contiene el proyecto

Cinco tablas: categoría, producto, cliente, pedido y detalle de pedido. Reglas mediante CHECK, UNIQUE, FK y triggers; consultas con JOIN, agregaciones, subconsultas y ventanas; índices medidos; tres vistas y una materializada; función de total y procedimientos de alta/baja; validación con tablas de transición; pruebas de COMMIT/ROLLBACK, aislamiento, concurrencia y borrado lógico.

La [reproducción del integrador](tpi/README.md#reproducción-desde-cero) crea una base nueva y no depende de bases locales anteriores. Los benchmarks masivos se conservan con sus planes originales en las carpetas de los trabajos prácticos.

## Trabajos anteriores conservados

| Trabajo | Contenido |
|---|---|
| Base del TP1 | [DDL](schema.sql); el modelo consolidado para esta entrega está en [tpi/modelo.md](tpi/modelo.md) |
| [TP2](README_TP2.md) | Integridad, transacciones, concurrencia y lectura crítica |
| [TP3](tp3/README.md) | Carga masiva, optimización y equivalencia |
| [TP4](tp4/README.md) | Reportes, joins, rankings y subconsultas |
| [TP5](tp5/README.md) | Índices, costo de escritura, vistas, permisos y materialización |

Los scripts nuevos del TPI están en `tpi/`; reutilizan el esquema y los archivos anteriores sin reescribir su historial. Los respaldos binarios, credenciales y guías personales no forman parte de la entrega.
