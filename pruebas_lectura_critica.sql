-- Esquema genérico mínimo de la consigna. Solo tablas temporales.
-- Ejecutar dentro de BEGIN ... ROLLBACK.
CREATE TEMP TABLE funcion (id INTEGER PRIMARY KEY, activa BOOLEAN, fecha_fin DATE);
INSERT INTO funcion VALUES (1, TRUE, CURRENT_DATE-1), (2, TRUE, CURRENT_DATE+1), (3, FALSE, CURRENT_DATE-2);
CREATE TEMP TABLE categoria_generica (id INTEGER PRIMARY KEY);
CREATE TEMP TABLE producto_generico (id INTEGER PRIMARY KEY, categoria_id INTEGER);
INSERT INTO categoria_generica VALUES (1),(2),(3);
INSERT INTO producto_generico VALUES (1,1),(2,NULL);

DO $$
DECLARE n INTEGER;
BEGIN
    UPDATE funcion SET activa=FALSE;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 3 THEN RAISE EXCEPTION 'UPDATE original: se esperaban 3 filas'; END IF;
    RAISE NOTICE 'OK: UPDATE sin WHERE afecta las 3 funciones';
    UPDATE funcion SET activa=TRUE WHERE id IN (1,2);
    UPDATE funcion SET activa=FALSE WHERE activa=TRUE AND fecha_fin<CURRENT_DATE;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 1 OR NOT (SELECT activa FROM funcion WHERE id=2) THEN
        RAISE EXCEPTION 'La correccion debe afectar solo la funcion vencida activa';
    END IF;
    RAISE NOTICE 'OK: UPDATE corregido afecta 1 funcion; la vigente sigue activa';

    DELETE FROM categoria_generica WHERE id NOT IN (SELECT categoria_id FROM producto_generico);
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 0 THEN RAISE EXCEPTION 'NOT IN con NULL no debe borrar categorias'; END IF;
    RAISE NOTICE 'OK: NOT IN con NULL afecta 0 categorias';
    DELETE FROM categoria_generica c WHERE NOT EXISTS
      (SELECT 1 FROM producto_generico p WHERE p.categoria_id=c.id);
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 2 OR (SELECT count(*) FROM categoria_generica) <> 1 THEN
        RAISE EXCEPTION 'NOT EXISTS debe borrar solo las 2 categorias sin productos';
    END IF;
    RAISE NOTICE 'OK: NOT EXISTS afecta 2 categorias; conserva la referenciada';
END;
$$;
