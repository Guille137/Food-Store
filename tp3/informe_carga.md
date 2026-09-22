# Parte 1 — Carga masiva y controles

Se aplicó [carga_masiva.sql](carga_masiva.sql) según [spec_carga.md](spec_carga.md), con generate_series y fórmulas deterministas. Los triggers del TP2 permanecieron activos. No se usaron datos personales reales.

| Entidad | Nuevas filas | Total con seed |
|---|---:|---:|
| producto | 50.000 | 50.003 |
| cliente (usuarios compradores) | 20.000 | 20.001 |
| pedido | 200.000 | 200.003 |
| detalle_pedido | 600.000 | 600.000 |

Distribución de productos nuevos: 16.667 en categoría 1, 16.667 en categoría 2 y 16.666 en categoría 3. Precios observados: 500,00 a 5.000,00. Stock: 1 a 200. Se eligió un mínimo de 1 para que cada detalle de cantidad 1 cumpliera el control de stock; el ejemplo de la consigna de stock 0–200 es orientativo, no una condición de la carga exigida.

Los pedidos se crearon PENDIENTE y sus detalles se insertaron antes de transitar de estado. Resultado con seed: 50.003 PENDIENTE, 50.000 CONFIRMADO, 50.000 ENTREGADO y 50.000 CANCELADO. Se desactivaron posteriormente 5.000 productos para representar bajas históricas; sus ventas previas se conservan.

## Protocolo ejecutado

1. Se creó `food_store_tp3_20260922_142245_plantilla` desde los tres scripts del proyecto. Se ensayó primero con ROLLBACK y se aplicó después con COMMIT.
2. Se creó la copia `_ensayo`, se respaldó antes de cargar y se ejecutó la carga completa con ROLLBACK. Los controles dentro de la transacción dieron los volúmenes exigidos; después del ROLLBACK el conteo de detalles fue 0.
3. Se creó otra copia `_trabajo` desde la plantilla limpia, se respaldó y se repitió la carga con COMMIT. No se reutilizó la copia de ensayo ni se desactivaron restricciones.
4. Se ejecutó VACUUM (ANALYZE), que incluye la actualización de estadísticas pedida, antes de medir.

Los dumps permanecen en `../backups/`, excluidos de Git, con nombres que empiezan por `food_store_tp3_20260922_142245`. La instancia y los respaldos locales se conservan para inspección. No se afirma haber ensayado una restauración.

La revisión del SQL comprueba nombres únicos, FKs obtenidas por RETURNING, cantidad positiva, precios NUMERIC, transiciones válidas y copia de precio histórico. La consulta de detalles con cantidad no positiva, superior al stock o precio negativo devolvió **0 filas**. Ver [consultas y controles reales](evidencias/20260922_142245/controles_carga.json).

La práctica continúa el mismo proyecto de los TP anteriores: schema.sql más restricciones_Food_Store.sql constituyen el esquema utilizado y datos_iniciales.sql aporta el seed. Se documenta esta correspondencia con schema_completo.sql/data.sql del PDF; no se creó un modelo ajeno al proyecto ni un repositorio distinto.
