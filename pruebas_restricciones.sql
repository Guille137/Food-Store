-- Ejecutar después de restricciones_food_store.sql, sobre datos de prueba.
-- Reemplazar los ids por ids existentes en la copia de trabajo.
BEGIN;

-- Prueba válida R1: PENDIENTE -> CONFIRMADO.
UPDATE pedido SET estado = 'CONFIRMADO' WHERE id_pedido = 1;

-- Prueba inválida R1: CONFIRMADO -> PENDIENTE. Debe lanzar 23514.
SAVEPOINT r1_invalida;
UPDATE pedido SET estado = 'PENDIENTE' WHERE id_pedido = 1;
ROLLBACK TO SAVEPOINT r1_invalida;

-- Prueba inválida R2: no se puede agregar un detalle a un pedido confirmado. Debe lanzar 23514.
SAVEPOINT r2_invalida;
INSERT INTO detalle_pedido (id_pedido, id_producto, precio_unitario, cantidad)
VALUES (1, 1, 100.00, 1);
ROLLBACK TO SAVEPOINT r2_invalida;

-- Preparar un pedido PENDIENTE (id 2) para R3.
-- Prueba válida R3: cantidad menor o igual al stock y producto activo.
INSERT INTO detalle_pedido (id_pedido, id_producto, precio_unitario, cantidad)
VALUES (2, 1, 100.00, 1);

-- Prueba inválida R3: cantidad mayor que el stock. Debe lanzar 23514.
SAVEPOINT r3_invalida;
INSERT INTO detalle_pedido (id_pedido, id_producto, precio_unitario, cantidad)
VALUES (2, 2, 100.00, 999999);
ROLLBACK TO SAVEPOINT r3_invalida;

ROLLBACK;