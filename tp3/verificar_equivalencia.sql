-- Ejecutar dentro de BEGIN ... ROLLBACK. No modifica datos permanentes.

CREATE TEMP VIEW tp3_resumen_a AS SELECT c.id_categoria, c.nombre, count(p.id_producto) AS cantidad_productos
FROM categoria c
LEFT JOIN producto p ON p.categoria_id=c.id_categoria AND p.activo=TRUE
WHERE c.activo=TRUE
GROUP BY c.id_categoria, c.nombre
ORDER BY cantidad_productos DESC, c.id_categoria ASC;

CREATE TEMP VIEW tp3_resumen_b AS SELECT c.id_categoria, c.nombre, coalesce(t.cantidad_productos,0) AS cantidad_productos
FROM categoria c
LEFT JOIN (
  SELECT categoria_id, count(*) AS cantidad_productos
  FROM producto WHERE activo=TRUE GROUP BY categoria_id
) t ON t.categoria_id=c.id_categoria
WHERE c.activo=TRUE
ORDER BY cantidad_productos DESC, c.id_categoria ASC;

CREATE TEMP VIEW tp3_subconsulta_a AS SELECT p.id_producto, p.nombre, p.precio_lista
FROM producto p
JOIN categoria c ON c.id_categoria=p.categoria_id
WHERE p.activo=TRUE AND c.activo=TRUE
  AND NOT EXISTS (
    SELECT 1 FROM detalle_pedido d
    JOIN pedido o ON o.id_pedido=d.id_pedido
    WHERE d.id_producto=p.id_producto AND o.estado<>'CANCELADO'
  )
ORDER BY p.id_producto ASC;

CREATE TEMP VIEW tp3_subconsulta_b AS SELECT p.id_producto, p.nombre, p.precio_lista
FROM producto p
JOIN categoria c ON c.id_categoria=p.categoria_id
LEFT JOIN (
  SELECT DISTINCT d.id_producto
  FROM detalle_pedido d
  JOIN pedido o ON o.id_pedido=d.id_pedido
  WHERE o.estado<>'CANCELADO'
) vendidos ON vendidos.id_producto=p.id_producto
WHERE p.activo=TRUE AND c.activo=TRUE AND vendidos.id_producto IS NULL
ORDER BY p.id_producto ASC;


SELECT 'masiva_resumen' AS prueba,
 (SELECT count(*) FROM tp3_resumen_a) AS filas_a,
 (SELECT count(*) FROM tp3_resumen_b) AS filas_b,
 (SELECT count(*) FROM (TABLE tp3_resumen_a EXCEPT ALL TABLE tp3_resumen_b) d) AS diferencias_a_b,
 (SELECT count(*) FROM (TABLE tp3_resumen_b EXCEPT ALL TABLE tp3_resumen_a) d) AS diferencias_b_a;
DO $$ BEGIN
 IF EXISTS(TABLE tp3_resumen_a EXCEPT ALL TABLE tp3_resumen_b) OR EXISTS(TABLE tp3_resumen_b EXCEPT ALL TABLE tp3_resumen_a) THEN
  RAISE EXCEPTION 'No son equivalentes: masiva_resumen';
 END IF;
END $$;



SELECT 'masiva_subconsulta' AS prueba,
 (SELECT count(*) FROM tp3_subconsulta_a) AS filas_a,
 (SELECT count(*) FROM tp3_subconsulta_b) AS filas_b,
 (SELECT count(*) FROM (TABLE tp3_subconsulta_a EXCEPT ALL TABLE tp3_subconsulta_b) d) AS diferencias_a_b,
 (SELECT count(*) FROM (TABLE tp3_subconsulta_b EXCEPT ALL TABLE tp3_subconsulta_a) d) AS diferencias_b_a;
DO $$ BEGIN
 IF EXISTS(TABLE tp3_subconsulta_a EXCEPT ALL TABLE tp3_subconsulta_b) OR EXISTS(TABLE tp3_subconsulta_b EXCEPT ALL TABLE tp3_subconsulta_a) THEN
  RAISE EXCEPTION 'No son equivalentes: masiva_subconsulta';
 END IF;
END $$;



CREATE TEMP TABLE tp3_bordes (caso TEXT PRIMARY KEY, id INTEGER);
DO $$
DECLARE vacia INTEGER; solo_inactivos INTEGER; inactiva INTEGER; pruebas INTEGER;
        sin_venta INTEGER; cancelado INTEGER; vigente INTEGER; invisible INTEGER;
        usuario INTEGER; orden INTEGER;
BEGIN
 INSERT INTO categoria(nombre) VALUES ('TP3 borde vacia') RETURNING id_categoria INTO vacia;
 INSERT INTO categoria(nombre) VALUES ('TP3 borde solo inactivos') RETURNING id_categoria INTO solo_inactivos;
 INSERT INTO categoria(nombre,activo) VALUES ('TP3 borde inactiva',FALSE) RETURNING id_categoria INTO inactiva;
 INSERT INTO categoria(nombre) VALUES ('TP3 borde ventas') RETURNING id_categoria INTO pruebas;
 INSERT INTO producto(nombre,precio_lista,stock,activo,categoria_id)
 VALUES ('TP3 borde producto inactivo',100,10,FALSE,solo_inactivos);
 INSERT INTO producto(nombre,precio_lista,stock,categoria_id)
 VALUES ('TP3 borde categoria inactiva',100,10,inactiva) RETURNING id_producto INTO invisible;
 INSERT INTO producto(nombre,precio_lista,stock,categoria_id)
 VALUES ('TP3 borde sin venta',100,10,pruebas) RETURNING id_producto INTO sin_venta;
 INSERT INTO producto(nombre,precio_lista,stock,categoria_id)
 VALUES ('TP3 borde solo cancelado',100,10,pruebas) RETURNING id_producto INTO cancelado;
 INSERT INTO producto(nombre,precio_lista,stock,categoria_id)
 VALUES ('TP3 borde vigente',100,10,pruebas) RETURNING id_producto INTO vigente;
 INSERT INTO cliente(correo_electronico,nombre,apellido)
 VALUES ('tp3_bordes@example.test','Borde','Prueba') RETURNING id_cliente INTO usuario;
 INSERT INTO pedido(forma_pago,cliente_id) VALUES('EFECTIVO',usuario) RETURNING id_pedido INTO orden;
 INSERT INTO detalle_pedido VALUES(orden,cancelado,100,1);
 UPDATE pedido SET estado='CANCELADO' WHERE id_pedido=orden;
 INSERT INTO pedido(forma_pago,cliente_id) VALUES('TARJETA',usuario) RETURNING id_pedido INTO orden;
 INSERT INTO detalle_pedido VALUES(orden,vigente,100,1);
 INSERT INTO tp3_bordes VALUES ('vacia',vacia),('solo_inactivos',solo_inactivos),
 ('categoria_inactiva',inactiva),('sin_venta',sin_venta),('solo_cancelado',cancelado),
 ('venta_vigente',vigente),('producto_invisible',invisible);
 IF (SELECT cantidad_productos FROM tp3_resumen_a WHERE id_categoria=vacia) IS DISTINCT FROM 0::bigint
 OR (SELECT cantidad_productos FROM tp3_resumen_a WHERE id_categoria=solo_inactivos) IS DISTINCT FROM 0::bigint
 OR EXISTS(SELECT 1 FROM tp3_resumen_a WHERE id_categoria=inactiva) THEN
  RAISE EXCEPTION 'El resumen no cumple los casos limite';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM tp3_subconsulta_a WHERE id_producto=sin_venta)
 OR NOT EXISTS(SELECT 1 FROM tp3_subconsulta_a WHERE id_producto=cancelado)
 OR EXISTS(SELECT 1 FROM tp3_subconsulta_a WHERE id_producto IN (vigente,invisible)) THEN
  RAISE EXCEPTION 'La subconsulta no cumple los casos limite';
 END IF;
END $$;
SELECT 'casos_limite' AS prueba, count(*) AS casos_comprobados FROM tp3_bordes;



SELECT 'bordes_resumen' AS prueba,
 (SELECT count(*) FROM tp3_resumen_a) AS filas_a,
 (SELECT count(*) FROM tp3_resumen_b) AS filas_b,
 (SELECT count(*) FROM (TABLE tp3_resumen_a EXCEPT ALL TABLE tp3_resumen_b) d) AS diferencias_a_b,
 (SELECT count(*) FROM (TABLE tp3_resumen_b EXCEPT ALL TABLE tp3_resumen_a) d) AS diferencias_b_a;
DO $$ BEGIN
 IF EXISTS(TABLE tp3_resumen_a EXCEPT ALL TABLE tp3_resumen_b) OR EXISTS(TABLE tp3_resumen_b EXCEPT ALL TABLE tp3_resumen_a) THEN
  RAISE EXCEPTION 'No son equivalentes: bordes_resumen';
 END IF;
END $$;



SELECT 'bordes_subconsulta' AS prueba,
 (SELECT count(*) FROM tp3_subconsulta_a) AS filas_a,
 (SELECT count(*) FROM tp3_subconsulta_b) AS filas_b,
 (SELECT count(*) FROM (TABLE tp3_subconsulta_a EXCEPT ALL TABLE tp3_subconsulta_b) d) AS diferencias_a_b,
 (SELECT count(*) FROM (TABLE tp3_subconsulta_b EXCEPT ALL TABLE tp3_subconsulta_a) d) AS diferencias_b_a;
DO $$ BEGIN
 IF EXISTS(TABLE tp3_subconsulta_a EXCEPT ALL TABLE tp3_subconsulta_b) OR EXISTS(TABLE tp3_subconsulta_b EXCEPT ALL TABLE tp3_subconsulta_a) THEN
  RAISE EXCEPTION 'No son equivalentes: bordes_subconsulta';
 END IF;
END $$;

