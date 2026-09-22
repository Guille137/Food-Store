-- Ejecutar exclusivamente dentro de BEGIN ... ROLLBACK con triggers activos.
CREATE TEMP TABLE tp4_bordes(caso TEXT PRIMARY KEY,id_cliente INTEGER,esperado NUMERIC);
DO $$
DECLARE cat INTEGER; prod INTEGER; cli INTEGER; ord INTEGER; i INTEGER; j INTEGER;
        caso TEXT; importe NUMERIC; fecha_borde TIMESTAMPTZ;
BEGIN
  INSERT INTO categoria(nombre) VALUES('TP4 categoria de prueba') RETURNING id_categoria INTO cat;
  INSERT INTO producto(nombre,precio_lista,stock,categoria_id)
  VALUES('TP4 producto de prueba',1000,20,cat) RETURNING id_producto INTO prod;
  FOR i IN 1..9 LOOP
    caso := (ARRAY['empate_a','empate_b','segundo','sin_pedidos','solo_cancelado',
                  'cero','entregado_vacio','umbral_exacto','fuera_periodo'])[i];
    INSERT INTO cliente(correo_electronico,nombre,apellido)
    VALUES('tp4_borde_'||i||'@example.test','Borde '||i,'TP4') RETURNING id_cliente INTO cli;
    INSERT INTO tp4_bordes VALUES(caso,cli,
      CASE WHEN i IN (1,2) THEN 1000000 WHEN i=3 THEN 500000 WHEN i=6 THEN 0 WHEN i=8 THEN 50000 ELSE NULL END);
    IF i=4 THEN CONTINUE; END IF;
    FOR j IN 1..CASE WHEN i=1 THEN 2 ELSE 1 END LOOP
      fecha_borde := CASE WHEN i=9 THEN TIMESTAMPTZ '2026-01-01 00:00:00+00'
                         ELSE TIMESTAMPTZ '2025-01-01 00:00:00+00' END;
      INSERT INTO pedido(fecha,forma_pago,cliente_id) VALUES(fecha_borde,'EFECTIVO',cli)
      RETURNING id_pedido INTO ord;
      importe:= CASE WHEN i=1 THEN 500000 WHEN i=2 THEN 1000000 WHEN i=3 THEN 500000
                     WHEN i=6 THEN 0 WHEN i=8 THEN 50000 ELSE 2000000 END;
      IF i<>7 THEN INSERT INTO detalle_pedido VALUES(ord,prod,importe,1); END IF;
      IF i=5 THEN
        UPDATE pedido SET estado='CANCELADO' WHERE id_pedido=ord;
      ELSE
        UPDATE pedido SET estado='CONFIRMADO' WHERE id_pedido=ord;
        UPDATE pedido SET estado='ENTREGADO' WHERE id_pedido=ord;
      END IF;
    END LOOP;
  END LOOP;
  -- La venta histórica debe permanecer aunque el catálogo se desactive después.
  UPDATE producto SET activo=FALSE WHERE id_producto=prod;
  UPDATE categoria SET activo=FALSE WHERE id_categoria=cat;
END;
$$;
SELECT caso,id_cliente,esperado FROM tp4_bordes ORDER BY caso;
