# DUIA de restricciones

La declaración completa y las salidas reales se mantienen en [duia_parte1.md](duia_parte1.md). Este enlace conserva el nombre usado en versiones anteriores.

Comprobación del 22/09/2026: PostgreSQL devolvió UPDATE 1 para la transición válida y SQLSTATE 23514 para las transiciones inválidas, pedidos confirmados, productos inactivos y cantidades excesivas. Las pruebas de restricciones se revirtieron; el conteo final de detalle_pedido fue 0.

La ampliación integradora tiene su [DUIA](tpi/duia.md) y [evidencia de 79 comprobaciones](tpi/resultados.md): incluye CALL, atomicidad, baja lógica y triggers con tablas de transición. Esta evidencia complementa la del TP2 sin reemplazarla.
La [Unidad 4](tpUnidad4/README.md) agrega FNBC y desnormalización. Ejecución del 30/09/2026 en PostgreSQL 17.11: 66 comprobaciones correctas, migración y auditoría sin diferencias; errores esperados 23502, 23503 y 23514, y rechazo 0A000 del aislamiento no admitido por la sincronización. Las salidas SQL y las mediciones reales están en [resultado.json](tpUnidad4/evidencias/20260930_190238_612510/resultado.json). Codex se utilizó para implementación, revisión y pruebas; no se atribuye uso de otras herramientas.