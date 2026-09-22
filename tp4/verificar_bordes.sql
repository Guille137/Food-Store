CREATE TEMP TABLE tp4_ranking_observado AS WITH gastos AS (
  SELECT u.id_cliente,u.nombre||' '||u.apellido AS nombre_completo,
         sum(d.cantidad*d.precio_unitario) AS total_gastado
  FROM cliente u JOIN pedido o ON o.cliente_id=u.id_cliente
  JOIN detalle_pedido d ON d.id_pedido=o.id_pedido
  WHERE o.estado='ENTREGADO'
    AND o.fecha>=TIMESTAMPTZ '2025-01-01 00:00:00+00'
    AND o.fecha<TIMESTAMPTZ '2026-01-01 00:00:00+00'
  GROUP BY u.id_cliente,u.nombre,u.apellido
)
SELECT id_cliente,nombre_completo,total_gastado,
       dense_rank() OVER (ORDER BY total_gastado DESC) AS puesto
FROM gastos
ORDER BY puesto ASC,id_cliente ASC;
CREATE TEMP TABLE tp4_correlacionada_observada AS SELECT u.id_cliente,u.nombre||' '||u.apellido AS nombre_completo,u.correo_electronico
FROM cliente u
WHERE (
  SELECT sum(d.cantidad*d.precio_unitario)
  FROM pedido o JOIN detalle_pedido d ON d.id_pedido=o.id_pedido
  WHERE o.cliente_id=u.id_cliente AND o.estado='ENTREGADO'
    AND o.fecha>=TIMESTAMPTZ '2025-01-01 00:00:00+00'
    AND o.fecha<TIMESTAMPTZ '2026-01-01 00:00:00+00'
)>50000
ORDER BY u.id_cliente ASC;
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM tp4_bordes b LEFT JOIN tp4_ranking_observado r USING(id_cliente)
           WHERE b.esperado IS NOT NULL AND r.total_gastado IS DISTINCT FROM b.esperado)
 OR EXISTS(SELECT 1 FROM tp4_bordes b JOIN tp4_ranking_observado r USING(id_cliente) WHERE b.esperado IS NULL)
 THEN RAISE EXCEPTION 'Ranking: importe o inclusion incorrectos'; END IF;
 IF (SELECT count(*) FROM tp4_bordes b JOIN tp4_ranking_observado r USING(id_cliente)
     WHERE b.caso IN ('empate_a','empate_b') AND r.puesto=1)<>2
 OR NOT EXISTS(SELECT 1 FROM tp4_bordes b JOIN tp4_ranking_observado r USING(id_cliente)
               WHERE b.caso='segundo' AND r.puesto=2)
 THEN RAISE EXCEPTION 'Ranking: los empates deben compartir puesto sin saltos'; END IF;
 IF EXISTS(SELECT 1 FROM tp4_bordes b LEFT JOIN tp4_correlacionada_observada c USING(id_cliente)
           WHERE coalesce(b.esperado>50000,FALSE) IS DISTINCT FROM (c.id_cliente IS NOT NULL))
 THEN RAISE EXCEPTION 'Correlacionada: umbral, NULL o inclusion incorrectos'; END IF;
END $$;
SELECT b.caso,b.esperado,r.total_gastado,r.puesto,(c.id_cliente IS NOT NULL) AS supera_umbral
FROM tp4_bordes b LEFT JOIN tp4_ranking_observado r USING(id_cliente)
LEFT JOIN tp4_correlacionada_observada c USING(id_cliente) ORDER BY b.caso;
