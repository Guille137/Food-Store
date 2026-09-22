-- I1 / Q1: B-tree de expresión; solo productos vigentes.
-- El UNIQUE heredado sobre nombre no resuelve igualdad sobre lower(nombre).
CREATE INDEX tp5_producto_nombre_activo
ON producto (lower(nombre)) WHERE activo;
