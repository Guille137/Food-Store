# Requisitos — Food Store sin conexión

Estos requisitos EARS se revisaron y ajustaron en Kiro durante la preparación final del TP.

| ID | Requisito EARS | Caso de prueba |
|---|---|---|
| REQ-01 | WHEN una solicitud pendiente contiene un producto inexistente, no disponible, dado de baja o con stock insuficiente, THE SYSTEM SHALL marcarla RECHAZADO; las restricciones STRICT de la tabla deben impedir insertar ítems con cantidad ≤ 0 o producto inexistente. | C3, C4, C7 |
| REQ-02 | WHEN todos los productos siguen disponibles y con stock suficiente, pero un precio visto difiere del snapshot, THE SYSTEM SHALL marcar la solicitud CONFLICTO. | C2 |
| REQ-03 | WHEN el catálogo local está disponible sin conexión y una solicitud pendiente coincide en disponibilidad, baja lógica, stock y precio con el snapshot, THE SYSTEM SHALL permitir consultar productos y marcar la solicitud SIMULADO_APROBADO sin confirmar una venta. | C1, C5 |
| REQ-04 | WHEN una solicitud se reenvía con un UUID ya almacenado, THE SYSTEM SHALL rechazar la clave duplicada y conservar el resultado ya procesado. | C6 |
