// Unidad 7 · Carga los documentos exportados por 01_exportar_pedidos.sql.
// Uso: mongosh "mongodb://127.0.0.1:27017/food_store" --eval "const ARCHIVO='ruta/pedidos.ndjson'" tpi2/u7/03_cargar_pedidos.js
// Convierte tipos (fecha -> Date, importes -> Decimal128, ids -> int32) y carga
// por lotes. Un documento que no pase el validador detiene la carga: no hay
// carga parcial silenciosa.

const fs = require('fs');
if (typeof ARCHIVO === 'undefined') { throw new Error('Definir ARCHIVO con la ruta del .ndjson'); }

const lineas = fs.readFileSync(ARCHIVO, 'utf8').split('\n').filter(l => l.trim() !== '');
const documentos = lineas.map(texto => {
  const d = JSON.parse(texto);
  return {
    _id: NumberInt(d._id),
    fecha: new Date(d.fecha),
    estado: d.estado,
    forma_pago: d.forma_pago,
    cliente: { id_cliente: NumberInt(d.cliente.id_cliente), nombre: d.cliente.nombre, apellido: d.cliente.apellido },
    lineas: d.lineas.map(l => ({
      id_producto: NumberInt(l.id_producto),
      producto: l.producto,
      categoria: l.categoria,
      cantidad: NumberInt(l.cantidad),
      precio_unitario: NumberDecimal(l.precio_unitario),
      subtotal: NumberDecimal(l.subtotal)
    })),
    total: NumberDecimal(d.total),
    cantidad_items: NumberInt(d.cantidad_items)
  };
});

let insertados = 0;
for (let i = 0; i < documentos.length; i += 500) {
  const r = db.pedidos.insertMany(documentos.slice(i, i + 500), { ordered: true });
  insertados += Object.keys(r.insertedIds).length;
}
printjson({ leidos: lineas.length, insertados: insertados, en_coleccion: db.pedidos.countDocuments() });
