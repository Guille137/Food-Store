-- Unidad 4, Parte 1. Ejecutar en una COPIA de Food Store, con transacción externa.
-- Primera instalación: no elimina ni reemplaza tablas de trabajos anteriores.
CREATE SCHEMA unidad4;
CREATE TABLE unidad4.lote (id BIGINT PRIMARY KEY, descripcion TEXT NOT NULL);
CREATE TABLE unidad4.deposito (id BIGINT PRIMARY KEY, nombre TEXT NOT NULL);
CREATE TABLE unidad4.usuario (id BIGINT PRIMARY KEY, nombre TEXT NOT NULL);
INSERT INTO unidad4.lote VALUES (501,'Lote 501'),(502,'Lote 502'),(503,'Lote 503');
INSERT INTO unidad4.deposito VALUES (30,'Central'),(31,'Norte');
INSERT INTO unidad4.usuario VALUES (801,'Responsable 801'),(802,'Responsable 802'),(803,'Responsable 803');

CREATE TABLE unidad4.control_lote_almacen (
    lote_id BIGINT NOT NULL REFERENCES unidad4.lote(id),
    deposito_id BIGINT NOT NULL REFERENCES unidad4.deposito(id),
    responsable_control_id BIGINT NOT NULL REFERENCES unidad4.usuario(id),
    PRIMARY KEY (lote_id, deposito_id)
);
INSERT INTO unidad4.control_lote_almacen VALUES (501,30,801),(502,30,801),(503,31,802);

CREATE TABLE unidad4.responsable_deposito (
    responsable_control_id BIGINT PRIMARY KEY REFERENCES unidad4.usuario(id),
    deposito_id BIGINT NOT NULL REFERENCES unidad4.deposito(id)
);
CREATE TABLE unidad4.control_lote (
    lote_id BIGINT NOT NULL REFERENCES unidad4.lote(id),
    responsable_control_id BIGINT NOT NULL REFERENCES unidad4.responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);
INSERT INTO unidad4.responsable_deposito
SELECT DISTINCT responsable_control_id, deposito_id FROM unidad4.control_lote_almacen;
INSERT INTO unidad4.control_lote
SELECT lote_id, responsable_control_id FROM unidad4.control_lote_almacen;
CREATE VIEW unidad4.vista_control_lote_almacen AS
SELECT lote_id, deposito_id, responsable_control_id
FROM unidad4.control_lote NATURAL JOIN unidad4.responsable_deposito;

-- R -> D queda preservada en responsable_deposito. LD -> R no es local
-- a ninguna tabla resultante: esta comprobación adicional preserva el negocio.
-- Serialización y snapshot nuevo de las consultas VOLATILE en READ COMMITTED.
CREATE FUNCTION unidad4.bloquear_lotes() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'La extensión de lotes requiere READ COMMITTED' USING ERRCODE='0A000';
    END IF;
    PERFORM pg_advisory_xact_lock(42004,1);
    RETURN NULL;
END $$;
CREATE FUNCTION unidad4.validar_lote_deposito() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM unidad4.vista_control_lote_almacen
               GROUP BY lote_id, deposito_id HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'Un lote y depósito no pueden tener dos responsables' USING ERRCODE='23514';
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER u4_lotes_bloqueo BEFORE INSERT OR UPDATE OR DELETE ON unidad4.control_lote
FOR EACH STATEMENT EXECUTE FUNCTION unidad4.bloquear_lotes();
CREATE TRIGGER u4_lotes_validacion AFTER INSERT OR UPDATE ON unidad4.control_lote
FOR EACH STATEMENT EXECUTE FUNCTION unidad4.validar_lote_deposito();
CREATE TRIGGER u4_responsables_bloqueo BEFORE INSERT OR UPDATE OR DELETE ON unidad4.responsable_deposito
FOR EACH STATEMENT EXECUTE FUNCTION unidad4.bloquear_lotes();
CREATE TRIGGER u4_responsables_validacion AFTER INSERT OR UPDATE ON unidad4.responsable_deposito
FOR EACH STATEMENT EXECUTE FUNCTION unidad4.validar_lote_deposito();

-- Original conservado únicamente como instantánea de la migración.
CREATE VIEW unidad4.auditoria_migracion AS
(SELECT * FROM unidad4.control_lote_almacen
 EXCEPT ALL SELECT * FROM unidad4.vista_control_lote_almacen)
UNION ALL
(SELECT * FROM unidad4.vista_control_lote_almacen
 EXCEPT ALL SELECT * FROM unidad4.control_lote_almacen);
SELECT * FROM unidad4.auditoria_migracion; -- 0 filas tras migrar.
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM unidad4.auditoria_migracion) THEN
        RAISE EXCEPTION 'La migración no es equivalente';
    END IF;
END $$;
