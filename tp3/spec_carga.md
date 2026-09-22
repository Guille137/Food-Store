# Especificación de la carga masiva

## Modelo de trabajo

Base propia Food Store del repositorio: `schema.sql`, `datos_iniciales.sql` y restricciones del TP2. El PDF menciona `schema_completo.sql`, `data.sql` y `queries.sql`, archivos no incluidos en el material disponible al iniciar el trabajo. Se usan variantes propias permitidas en la Parte 2. La entidad de usuarios compradores corresponde a `cliente`; la baja lógica se expresa con `activo`, no con `eliminado`.

## Generación requerida

- Agregar 50.000 productos repartidos entre las categorías vigentes existentes; nombres únicos con prefijo TP3, precios entre 500 y 5.000, stock inicial entre 1 y 200 para admitir detalles válidos.
- Agregar 20.000 clientes con correos únicos bajo example.test.
- Agregar 200.000 pedidos con tres líneas distintas cada uno (600.000 detalles), fecha determinista repartida en 2025 y clientes distribuidos de forma repetible.
- Insertar los pedidos en PENDIENTE, agregar sus detalles y luego transitar a CONFIRMADO, ENTREGADO o CANCELADO respetando los triggers del TP2. Conservar parte de los pedidos pendientes.
- Crear los detalles con cantidad 1 y precio de lista copiado a precio_unitario. No se desactivan triggers ni restricciones.
- Marcar posteriormente una fracción de productos inactiva para representar bajas lógicas históricas sin borrar datos.
- No reutilizar una base existente ni ejecutar la carga dos veces sobre la misma copia. Los scripts se ejecutan con BEGIN y se inspeccionan primero con ROLLBACK.
- Respaldar antes de cargar o cambiar la estructura. Correr ANALYZE antes de medir. No desactivar escaneos secuenciales ni forzar el uso de índices.

Se emplean fórmulas deterministas con generate_series, sin datos personales reales. Los volúmenes y distribuciones se verifican con consultas después de la carga.
