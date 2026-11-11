// Unidad 7 · Consultas documentales sobre la colección pedidos.
// Uso: mongosh "mongodb://127.0.0.1:27017/food_store" tpi2/u7/04_consultas.js
// Imprime UN documento JSON con el resultado de cada consulta, su plan (índice
// usado, documentos examinados) y la mediana de 30 ejecuciones. Las consultas
// equivalentes en SQL están en 05_consultas.sql, con las mismas claves de
// resultado, para compararlas automáticamente.

const PRODUCTO = 1;
const CLIENTE = 7;
const PEDIDO = 1500;
const UMBRAL_TOTAL = NumberDecimal('20000');
const dinero = v => (v === null || v === undefined) ? null : Number(v.toString()).toFixed(2);

const consultas = {
  // C1. Pedido completo por id: el caso de uso principal (una lectura, sin JOIN).
  c1_pedido_completo: {
    tipo: 'find',
    ejecutar: () => db.pedidos.findOne({ _id: PEDIDO }),
    plan: () => db.pedidos.find({ _id: PEDIDO }).explain('executionStats'),
    normalizar: d => ({ id_pedido: d._id, estado: d.estado, cliente: d.cliente.id_cliente,
                        total: dinero(d.total),
                        lineas: d.lineas.map(l => [l.id_producto, l.cantidad, dinero(l.precio_unitario)]) })
  },
  // C2. Cantidad de pedidos por estado.
  c2_pedidos_por_estado: {
    tipo: 'aggregate',
    pipeline: [{ $group: { _id: '$estado', pedidos: { $sum: 1 } } }, { $sort: { _id: 1 } }],
    normalizar: r => r.map(x => [x._id, x.pedidos])
  },
  // C3. Pedidos que incluyen un producto (consulta dentro del arreglo, índice multiclave).
  c3_pedidos_con_producto: {
    tipo: 'find',
    ejecutar: () => db.pedidos.find({ 'lineas.id_producto': PRODUCTO }, { _id: 1 }).sort({ _id: 1 }).toArray(),
    plan: () => db.pedidos.find({ 'lineas.id_producto': PRODUCTO }, { _id: 1 }).sort({ _id: 1 }).explain('executionStats'),
    normalizar: r => ({ cantidad: r.length, ids: r.map(x => x._id) })
  },
  // C4. Pedidos entregados con total mayor al umbral.
  c4_entregados_total_alto: {
    tipo: 'find',
    ejecutar: () => db.pedidos.find({ estado: 'ENTREGADO', total: { $gt: UMBRAL_TOTAL } }, { _id: 1, total: 1 })
                      .sort({ total: -1, _id: 1 }).toArray(),
    plan: () => db.pedidos.find({ estado: 'ENTREGADO', total: { $gt: UMBRAL_TOTAL } }, { _id: 1, total: 1 })
                  .sort({ total: -1, _id: 1 }).explain('executionStats'),
    normalizar: r => r.map(x => [x._id, dinero(x.total)])
  },
  // C5. Facturación por categoría y mes (pedidos entregados), con $unwind del arreglo.
  c5_facturacion_categoria_mes: {
    tipo: 'aggregate',
    pipeline: [
      { $match: { estado: 'ENTREGADO' } },
      { $unwind: '$lineas' },
      { $group: { _id: { categoria: '$lineas.categoria',
                         mes: { $dateToString: { format: '%Y-%m', date: '$fecha', timezone: 'America/Argentina/Buenos_Aires' } } },
                  importe: { $sum: '$lineas.subtotal' }, unidades: { $sum: '$lineas.cantidad' } } },
      { $sort: { '_id.categoria': 1, '_id.mes': 1 } }
    ],
    normalizar: r => r.map(x => [x._id.categoria, x._id.mes, dinero(x.importe), x.unidades])
  },
  // C6. Los 5 clientes que más gastaron (pedidos entregados).
  c6_top_clientes: {
    tipo: 'aggregate',
    pipeline: [
      { $match: { estado: 'ENTREGADO' } },
      { $group: { _id: '$cliente.id_cliente', gastado: { $sum: '$total' }, pedidos: { $sum: 1 } } },
      { $sort: { gastado: -1, _id: 1 } },
      { $limit: 5 }
    ],
    normalizar: r => r.map(x => [x._id, dinero(x.gastado), x.pedidos])
  },
  // C7. Historial de un cliente, más reciente primero.
  c7_historial_cliente: {
    tipo: 'find',
    ejecutar: () => db.pedidos.find({ 'cliente.id_cliente': CLIENTE }, { _id: 1, fecha: 1, total: 1 })
                      .sort({ fecha: -1 }).toArray(),
    plan: () => db.pedidos.find({ 'cliente.id_cliente': CLIENTE }, { _id: 1, fecha: 1, total: 1 })
                  .sort({ fecha: -1 }).explain('executionStats'),
    normalizar: r => r.map(x => [x._id, dinero(x.total)])
  },
  // C8. Ticket promedio por forma de pago (excluye cancelados).
  c8_ticket_por_forma_pago: {
    tipo: 'aggregate',
    pipeline: [
      { $match: { estado: { $ne: 'CANCELADO' } } },
      { $group: { _id: '$forma_pago', pedidos: { $sum: 1 }, promedio: { $avg: '$total' } } },
      { $sort: { _id: 1 } }
    ],
    normalizar: r => r.map(x => [x._id, x.pedidos, dinero(x.promedio)])
  }
};

function mediana(fn, n) {
  const t = [];
  for (let i = 0; i < n; i++) { const a = process.hrtime.bigint(); fn(); t.push(Number(process.hrtime.bigint() - a) / 1e6); }
  t.sort((x, y) => x - y);
  return Number(t[Math.floor(n / 2)].toFixed(3));
}

function resumenPlan(e) {
  const s = e.executionStats;
  const etapas = [];
  (function recorrer(n) { if (!n) return; etapas.push(n.stage + (n.indexName ? '(' + n.indexName + ')' : ''));
    recorrer(n.inputStage); (n.inputStages || []).forEach(recorrer); })(e.queryPlanner.winningPlan.queryPlan || e.queryPlanner.winningPlan);
  return { etapas: etapas.join(' <- '), documentos_examinados: s.totalDocsExamined, claves_examinadas: s.totalKeysExamined,
           devueltos: s.nReturned };
}

const salida = { coleccion: db.pedidos.countDocuments(), consultas: {} };
for (const [nombre, c] of Object.entries(consultas)) {
  const ejecutar = c.tipo === 'aggregate' ? () => db.pedidos.aggregate(c.pipeline).toArray() : c.ejecutar;
  const plan = c.tipo === 'aggregate' ? db.pedidos.explain('executionStats').aggregate(c.pipeline) : c.plan();
  let resumen;
  try { resumen = resumenPlan(plan.stages ? plan.stages[0].$cursor : plan); } catch (e) { resumen = { etapas: 'ver explain' }; }
  salida.consultas[nombre] = { resultado: c.normalizar(ejecutar()), plan: resumen, mediana_ms: mediana(ejecutar, 30) };
}
print(JSON.stringify(salida));
