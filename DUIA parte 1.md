# DUIA de restricciones

La declaración completa y las salidas reales se mantienen en [duia_parte1.md](duia_parte1.md). Este enlace conserva el nombre usado en versiones anteriores.

Comprobación del 22/09/2026: PostgreSQL devolvió UPDATE 1 para la transición válida y SQLSTATE 23514 para las transiciones inválidas, pedidos confirmados, productos inactivos y cantidades excesivas. Las pruebas de restricciones se revirtieron; el conteo final de detalle_pedido fue 0.
