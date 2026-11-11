# Requisitos — Modelo documental de pedidos en MongoDB (Unidad 7)

## Introducción

La consulta más frecuente de Food Store es "mostrar un pedido completo" (cabecera, cliente y líneas). Se modela esa parte del dominio en MongoDB y se la compara, con datos reales del proyecto, contra la solución relacional. Esta spec amplía la entrega de `unidad 7/` (5 pedidos de ejemplo) a todos los pedidos de la base.

## Requisito 1 — Modelo y migración

1. EL SISTEMA DEBERÁ exportar desde PostgreSQL un documento por pedido con líneas, con cliente y líneas embebidos.
2. Los importes DEBERÁN cargarse como `Decimal128`, nunca como `double`.
3. Del cliente solo DEBERÁN viajar id, nombre y apellido (sin correo ni teléfono).
4. CUANDO termine la carga, la cantidad de documentos DEBERÁ ser igual a la cantidad de pedidos con líneas.

## Requisito 2 — Integridad en la colección

1. La colección DEBERÁ rechazar documentos con: total distinto de la suma de líneas, cantidad ≤ 0, estado o forma de pago inexistentes, importes no decimales, campos no previstos, pedido sin líneas o producto repetido.
2. EL SISTEMA DEBERÁ documentar qué reglas del modelo relacional NO pueden garantizarse en MongoDB (claves foráneas).

## Requisito 3 — Consultas verificadas

1. EL SISTEMA DEBERÁ ofrecer al menos ocho consultas documentales (búsqueda por id, por estado, dentro del arreglo, por umbral, agregaciones con `$unwind`, ranking, historial, promedio).
2. CUANDO se ejecuten las consultas equivalentes en PostgreSQL, los resultados DEBERÁN ser idénticos, comparados automáticamente.
3. EL SISTEMA DEBERÁ registrar el plan de cada consulta MongoDB (índice usado, documentos examinados) y la mediana de 30 ejecuciones en cada motor.

## Requisito 4 — Comparación y decisión

1. EL SISTEMA DEBERÁ medir el costo de la duplicación (documentos a modificar por un cambio de dato del cliente).
2. El equipo DEBERÁ documentar qué tecnología se selecciona para cada uso y por qué.
