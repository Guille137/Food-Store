# Informe técnico — Parcial 1 - TPI

**Grupo: Octavio Skumanic, Sebastián Vivanco, Victoria Guzman, Daniela Sosa, Guillermo Sanchez**

**Base de Datos II · Food Store · 22/09/2026**

Avances de unidades 1, 2 y 3 sobre PostgreSQL 17.11: cinco tablas, modelo ER/relacional y BCNF, reglas de integridad, consultas optimizadas, vistas, funciones, procedimientos y pruebas de transacciones/borrado lógico. El [mapa de nueve objetivos](README.md#matriz-de-los-nueve-objetivos) vincula cada requisito con su implementación y evidencia.

## 1. Implementación por unidad

**Unidad 1: modelo, integridad, transacciones y concurrencia.** Se documentaron entidades, atributos, claves, cardinalidades y participación, corrigiendo la correspondencia con el DDL existente. Las relaciones 1:N usan FK en el lado dependiente y Pedido–Producto se resuelve con DetallePedido. Se justificó BCNF mediante dependencias funcionales y claves candidatas por relación.

El DDL utiliza ENUM, TIMESTAMPTZ, IDENTITY, PK, FK, NOT NULL, UNIQUE y CHECK. Los triggers controlan transiciones de estado, edición de detalles exclusivamente en pedidos pendientes, producto activo y stock suficiente por línea. El TP2 acredita COMMIT/ROLLBACK y comportamiento de READ COMMITTED y REPEATABLE READ con dos sesiones.

**Unidad 2: consultas y optimización.** Se generaron 50.000 productos, 20.000 clientes, 200.000 pedidos y 600.000 detalles adicionales. Se desarrollaron JOIN, agregaciones, GROUP BY/HAVING, subconsultas y ranking con DENSE_RANK. Se compararon planes antes/después de índices y reescrituras y se verificó equivalencia, incluidos empates y casos límite. Se conservaron propuestas descartadas: una reescritura de A1 fue más lenta que la consulta original con índices.

**Unidad 3: índices, vistas y objetos programables.** Se agregaron tres índices medidos y se evaluó su costo de escritura. Tres vistas permiten consultar catálogo vigente, pedidos/clientes sin contacto y detalles históricos. Una materializada resume facturación mensual del catálogo vigente y dispone de índice único para REFRESH CONCURRENTLY.

Para el TPI se completaron una función PL/pgSQL de total histórico y dos procedimientos invocados con CALL: alta de pedido desde JSONB y baja lógica de producto. Dos triggers por sentencia usan tablas de transición para rechazar líneas de categorías inactivas. Se conservan las tablas y funciones anteriores; la comprobación de categoría activa es una regla adicional de esta etapa.

## 2. Pruebas y resultados

La instalación independiente creó una base nueva y pasó **79 comprobaciones**, incluyendo ensayo reversible del DDL, llamadas correctas, errores esperados, atomicidad, COMMIT/ROLLBACK, concurrencia y equivalencia de vistas. [Resumen](resultados.md) y [registro SQL completo](evidencias/20260922_204000_480700/resultado.json).

- Un pedido de dos líneas devolvió total 45. Si la segunda supera el stock, se rechaza toda la llamada sin cabecera ni detalles parciales.
- Pedido vacío: cero; inexistente: P0002. Se rechazan JSONB inválido, referencias inexistentes, cantidades/precios negativos y transiciones inválidas.
- La baja conserva producto, referencias, precio de venta e historia, pero lo excluye del catálogo y de nuevas ventas. Conserva el nombre único. La consulta con índice parcial devuelve una fila antes y cero después.
- Otra conexión no ve el pedido sin confirmar y lo ve después de COMMIT. ROLLBACK elimina cabecera y detalles. Ante una baja de categoría concurrente, la venta espera un bloqueo real y luego se rechaza si la baja se confirma.
- Las tres vistas presentan cero diferencias frente a sus consultas de contraste. La prueba de permisos del TP5 permitió leer la vista y rechazó acceso a tablas y columnas de contacto. La materializada se actualizó mediante REFRESH CONCURRENTLY.

Los casos negativos usan SAVEPOINT o subtransacciones. Se respaldó antes del DDL y no se utilizaron bases productivas. Las 79 comprobaciones incluyen ensayo y versión definitiva; no son 79 reglas distintas.

## 3. Consultas optimizadas

Medianas de cinco muestras con caché caliente, de las sesiones publicadas de TP4/TP5. No se mezclan con la instalación funcional pequeña del TPI.

| Consulta | Antes (ms) | Después (ms) | Decisión |
|---|---:|---:|---|
| A1: facturación de junio por categoría | 89,276 | 64,069 | Original con índices; reescritura descartada |
| A2: clientes por gasto entregado | 186,607 | 145,723 | Índices y preagregación |
| Nombre de producto sin distinguir mayúsculas | 9,870 | 0,024 | Índice de expresión parcial; Seq Scan → Bitmap |
| Confirmados con tarjeta | 19,342 | 2,776 | Índice parcial cubierto; elimina Seq Scan y ordenamiento |
| Detalle con precio histórico alto | 58,102 | 0,311 | Índice por precio; recorrido paralelo → Index Only Scan |
| Agregado mensual frente a lectura materializada | 217,223 | 0,024 | Lee 39 filas precalculadas; REFRESH separado |

800 INSERT individuales pasaron de 180,269 a 188,844 ms (+4,76%); el lote de 800 filas, de 47,392 a 50,960 ms (+7,53%). Se descartó otro índice de detalle por pedido porque la PK y el índice cubierto previo ya dan ese acceso. [Planes/metodología TP4](../tp4/informe_optimizacion.md), [lectura/escritura TP5](../tp5/informe_mediciones.md).

Se propone refrescar la materializada cada 15 minutos y después del cierre mensual; no se instaló un programador. La lectura no incluye el costo de recalcular: los REFRESH probados duraron aproximadamente 325–338 ms. Entre refrescos o ante una falla, el dato puede quedar atrasado.

## 4. Uso de IA y decisiones

Se utilizó **Codex** para especificar, producir SQL/Python, revisar planes, ejecutar pruebas y documentar. No se atribuye uso a Kiro/OpenCode. Las [DUIA](duia.md) registran contexto, propuestas y decisiones.

Se aceptaron índices con mejora observada, vistas equivalentes y procedimientos atómicos. Se descartaron sobreindexación, una reescritura más lenta y almacenar un total redundante. Se conservó el precio de venta histórico y se rechazó transformar la baja en DELETE. El JSONB se transforma en filas normalizadas; no reemplaza las tablas.

## 5. Alcance

El stock se valida por línea, sin reserva/descuento automático. Cliente no almacena contraseña: la vista protege correo/teléfono existentes. La baja lógica corresponde a producto/categoría; CANCELADO es un estado del pedido. Los reportes históricos conservan ventas; A1/materializada filtra catálogo vigente por definición. Los nuevos objetos son SECURITY INVOKER y el llamador decide COMMIT/ROLLBACK.

Referencias del motor utilizadas: [CREATE PROCEDURE](https://www.postgresql.org/docs/17/sql-createprocedure.html), [transacciones PL/pgSQL](https://www.postgresql.org/docs/17/plpgsql-transactions.html) y [funciones de trigger/tablas de transición](https://www.postgresql.org/docs/17/plpgsql-trigger.html).
