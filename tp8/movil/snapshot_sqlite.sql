-- Crear esta tabla una vez en la base SQLite antes de importar el CSV.
-- El importador psql escribe booleanos como t/f, que se guardan como texto.
CREATE TABLE IF NOT EXISTS snapshot_servidor (
    id INTEGER PRIMARY KEY,
    nombre TEXT NOT NULL,
    precio_centavos INTEGER NOT NULL,
    stock INTEGER NOT NULL,
    disponible TEXT NOT NULL CHECK (disponible IN ('t', 'f')),
    eliminado TEXT NOT NULL CHECK (eliminado IN ('t', 'f'))
) STRICT;

-- Reemplazar snapshot sin borrar la instantánea anterior hasta tener el CSV nuevo:
-- DELETE FROM snapshot_servidor;
-- .import --csv --skip 1 servidor_snapshot.csv snapshot_servidor
