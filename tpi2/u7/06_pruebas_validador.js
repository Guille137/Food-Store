// Unidad 7 · Pruebas del validador y de la duplicación controlada.
// Uso: mongosh "mongodb://127.0.0.1:27017/food_store" tpi2/u7/06_pruebas_validador.js
// No deja cambios: los inserts inválidos son rechazados y los cambios de la
// prueba de duplicación se deshacen al final.

const base = db.pedidos.findOne({ _id: 1500 });
const copia = (cambios) => Object.assign(JSON.parse(EJSON.stringify(base, { relaxed: false }), (k, v) => v), cambios);
function intentar(nombre, documento) {
  try {
    db.pedidos.insertOne(EJSON.deserialize(documento));
    db.pedidos.deleteOne({ _id: EJSON.deserialize(documento)._id });
    return { prueba: nombre, rechazado: false };
  } catch (e) {
    return { prueba: nombre, rechazado: e.code === 121, codigo: e.code };   // 121 = DocumentValidationFailure
  }
}
const nuevoId = { $numberInt: '999999' };
const lineaMala = (c) => [Object.assign(JSON.parse(EJSON.stringify(base.lineas[0], { relaxed: false })), c)];

const pruebas = [
  intentar('documento válido (control)', copia({ _id: nuevoId })),
  intentar('total que no coincide con las líneas', copia({ _id: nuevoId, total: { $numberDecimal: '1.00' } })),
  intentar('cantidad cero', copia({ _id: nuevoId, lineas: lineaMala({ cantidad: { $numberInt: '0' } }) })),
  intentar('estado inexistente', copia({ _id: nuevoId, estado: 'PERDIDO' })),
  intentar('importe como double en lugar de Decimal128', copia({ _id: nuevoId, total: { $numberDouble: '10600.0' } })),
  intentar('campo no previsto (correo del cliente)', copia({ _id: nuevoId,
            cliente: { id_cliente: { $numberInt: '51' }, nombre: 'X', apellido: 'Y', correo: 'x@example.test' } })),
  intentar('pedido sin líneas', copia({ _id: nuevoId, lineas: [], total: { $numberDecimal: '0' },
            cantidad_items: { $numberInt: '0' } })),
  intentar('producto repetido en el pedido', copia({ _id: nuevoId,
            lineas: [JSON.parse(EJSON.stringify(base.lineas[0], { relaxed: false })), JSON.parse(EJSON.stringify(base.lineas[0], { relaxed: false }))],
            total: { $numberDecimal: (Number(base.total.toString()) * 2).toFixed(2) },
            cantidad_items: { $numberInt: String(base.cantidad_items * 2) } })),
  intentar('id de pedido duplicado', copia({}))
];

// Duplicación controlada: el nombre del cliente está copiado en cada pedido.
// Corregirlo en PostgreSQL es UPDATE de 1 fila; acá hay que tocar todos sus pedidos.
const cliente = base.cliente.id_cliente;
const afectados = db.pedidos.updateMany({ 'cliente.id_cliente': cliente },
                                        { $set: { 'cliente.apellido': 'Corregido' } });
db.pedidos.updateMany({ 'cliente.id_cliente': cliente }, { $set: { 'cliente.apellido': base.cliente.apellido } });

print(JSON.stringify({ pruebas: pruebas,
  duplicacion: { cliente: cliente, documentos_a_modificar_por_un_cambio_de_apellido: afectados.modifiedCount,
                 filas_a_modificar_en_postgresql: 1 },
  documentos_finales: db.pedidos.countDocuments() }));
