# Especificación previa — cierre de unidades 1, 2 y 3

Fuente: condiciones de la primera entrega parcial del TPI aportadas por el alumno. Continuar el mismo Food Store en PostgreSQL 16+; usar las cinco tablas, claves, tipos y reglas existentes. No sustituir los TP anteriores ni incluir guías personales. Herramienta autorizada: Codex; declarar uso real.

## Función tpi_total_pedido(integer)

PL/pgSQL, SECURITY INVOKER, retorno NUMERIC, consulta sin escrituras. Sumar cantidad*precio_unitario de los detalles; no usar precio actual ni filtrar bajas del catálogo/estado. Pedido vacío devuelve cero; inexistente o NULL provoca P0002. Probar valor exacto, vacío, inexistente y permanencia del total tras bajas y cambio de precio actual.

## Procedimiento tpi_registrar_pedido(integer, forma_pago, jsonb, INOUT integer)

Recibir cliente, pago, arreglo JSONB no vacío de objetos con id_producto y cantidad enteros positivos, y salida de id inicialmente NULL. Crear pedido PENDIENTE y sus detalles con precio actual como precio de venta. Rechazar claves adicionales, tipos incorrectos y productos repetidos (22023); las referencias, restricciones y stock deben seguir validados por PostgreSQL. Leer/bloquear productos por id ascendente con FOR SHARE, conservando precio y vigencia durante el alta. No descontar ni reservar stock: conservar la regla heredada por línea.

El CALL participa en la transacción del llamador, sin COMMIT interno. Si falla una línea posterior, no queda cabecera ni líneas parciales. Probar un pedido válido, persistencia después de COMMIT, desaparición después de ROLLBACK, fallo posterior al primer detalle, JSON inválido, cliente inexistente y producto inactivo. Contrastar visibilidad con una segunda conexión. No reutilizar valores de secuencias como garantía de ausencia de escrituras: las secuencias pueden avanzar al revertir.

## Procedimiento tpi_baja_producto(integer)

UPDATE activo=false sin DELETE. P0002 si no existe. Idempotente para uno ya inactivo. Mantener detalles históricos, precio de venta, total y FK; desaparecer del catálogo vigente y de consultas con predicado activo. El UNIQUE de nombre se conserva global: no reutilizar nombres de productos inactivos. Probar rechazo de una venta nueva y de nombre duplicado, historial inalterado y planes antes/después sobre el índice parcial.

## Categorías y tablas de transición

Agregar función trigger PL/pgSQL y dos triggers AFTER INSERT/UPDATE, por sentencia, sobre detalle_pedido, con REFERENCING NEW TABLE. Validar en conjunto las categorías de las filas nuevas; bloquear categorías por id ascendente con FOR SHARE. Rechazar categoría inactiva con 23514. Se agrega esta regla al TPI, sin reemplazar las funciones previas. Conserva historia al dar de baja la categoría: la baja no actualiza ni elimina detalles ya guardados. Las nuevas ventas/ediciones deben usar categorías activas. No propagar activo=false a productos: la vista de catálogo comprueba ambas vigencias. Probar INSERT y UPDATE de varias filas, rechazo atómico y bloqueo ante baja concurrente.

## Validación y reproducibilidad

Ejecutor independiente que crea una base nueva vacía, instala schema, seed, restricciones e índices/vistas de TP3–TP5, sin necesitar sus bases locales ni generar 600.000 filas para las pruebas funcionales. Antes de DDL: respaldo; cada bloque se ensaya con ROLLBACK y luego se confirma. Comprobar resultados reales antes de versionar los objetos. Las mediciones masivas ya publicadas siguen siendo evidencia de rendimiento; esta prueba pequeña comprueba instalación, reglas y transacciones, no sustituye los benchmarks.

Conservar salida SQL/SQLSTATE, versión, conteos, prueba en dos conexiones, planes de baja lógica y definiciones de objetos en JSON. Probar función, CALL, triggers existentes/nuevos, CHECK/UNIQUE/FK, vistas y materialización. Restaurar las bajas de prueba con ROLLBACK. Publicar resumen legible y mapa de nueve objetivos con vínculos exactos.
