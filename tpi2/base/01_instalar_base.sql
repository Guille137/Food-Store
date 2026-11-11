-- Segunda entrega TPI · Base común de laboratorio.
-- Ejecutar con psql DESDE LA RAÍZ del repositorio, sobre una base NUEVA y vacía:
--   createdb food_store_tpi2
--   psql -X -v ON_ERROR_STOP=1 -d food_store_tpi2 -f tpi2/base/01_instalar_base.sql
-- schema.sql comienza con DROP TABLE ... CASCADE: por eso se exige base vacía.
\set ON_ERROR_STOP on
SELECT current_database() AS base, current_user AS usuario, version() AS motor;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public') THEN
        RAISE EXCEPTION 'La base % ya tiene tablas en public: usar una base nueva', current_database();
    END IF;
END $$;

-- Toda la instalación es una única transacción: o queda completa o no queda nada.
-- Los scripts de la Unidad 4 además exigen transacción externa (usan LOCK TABLE).
BEGIN;

-- Esquema y reglas de las unidades 1 a 3 (entrega anterior), sin modificarlos.
\i schema.sql
\i restricciones_Food_Store.sql
\i tp3/indices.sql
\i tp4/indices.sql
\i tp5/indices.sql
\i tp5/views.sql
\i tpi/funciones.sql
\i tpi/registrar_pedido.sql
\i tpi/baja_producto.sql
\i tpi/categorias_transicion.sql

-- Datos sintéticos deterministas (ningún dato personal real).
\i tpi2/base/02_datos_sinteticos.sql

-- La materializada mensual se crea con los datos ya cargados.
\i tp5/materializadas.sql

-- Unidad 4 previa: FNBC de lotes y desnormalización controlada con triggers.
\i tpUnidad4/tp_fnbc_control_lote.sql
\i tpUnidad4/tp_desnormalizacion_top_categorias.sql

COMMIT;

ANALYZE;
SELECT 'categoria' AS tabla, count(*) FROM categoria
UNION ALL SELECT 'producto', count(*) FROM producto
UNION ALL SELECT 'cliente', count(*) FROM cliente
UNION ALL SELECT 'pedido', count(*) FROM pedido
UNION ALL SELECT 'detalle_pedido', count(*) FROM detalle_pedido
ORDER BY 1;
