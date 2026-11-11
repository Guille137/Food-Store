// Unidad 7 · Colección "pedidos" con validación de esquema e índices.
// Uso: mongosh "mongodb://127.0.0.1:27017/food_store" tpi2/u7/02_crear_coleccion.js
// Elimina y recrea SOLO la colección pedidos de la base indicada en la URI.
//
// MongoDB no tiene claves foráneas ni CHECK como PostgreSQL: lo que se pueda
// exigir se exige acá, en el validador ($jsonSchema + $expr). Lo que no se puede
// exigir (por ejemplo, que el id_cliente exista) queda a cargo del proceso de carga.

db.pedidos.drop();

const decimal = { bsonType: 'decimal' };
db.createCollection('pedidos', {
  validationLevel: 'strict',
  validationAction: 'error',
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['_id', 'fecha', 'estado', 'forma_pago', 'cliente', 'lineas', 'total', 'cantidad_items'],
      additionalProperties: false,
      properties: {
        _id: { bsonType: 'int', minimum: 1, description: 'id_pedido de PostgreSQL' },
        fecha: { bsonType: 'date' },
        estado: { enum: ['PENDIENTE', 'CONFIRMADO', 'ENTREGADO', 'CANCELADO'] },
        forma_pago: { enum: ['EFECTIVO', 'TARJETA', 'TRANSFERENCIA'] },
        cliente: {
          bsonType: 'object',
          required: ['id_cliente', 'nombre', 'apellido'],
          additionalProperties: false,
          properties: {
            id_cliente: { bsonType: 'int', minimum: 1 },
            nombre: { bsonType: 'string', minLength: 1 },
            apellido: { bsonType: 'string', minLength: 1 }
          }
        },
        lineas: {
          bsonType: 'array',
          minItems: 1,
          items: {
            bsonType: 'object',
            required: ['id_producto', 'producto', 'categoria', 'cantidad', 'precio_unitario', 'subtotal'],
            additionalProperties: false,
            properties: {
              id_producto: { bsonType: 'int', minimum: 1 },
              producto: { bsonType: 'string', minLength: 1 },
              categoria: { bsonType: 'string', minLength: 1 },
              cantidad: { bsonType: 'int', minimum: 1 },
              precio_unitario: decimal,
              subtotal: decimal
            }
          }
        },
        total: decimal,
        cantidad_items: { bsonType: 'int', minimum: 1 }
      }
    },
    // Reglas entre campos: precio no negativo, total = suma de subtotales y
    // ningún producto repetido dentro del mismo pedido (la PK de detalle_pedido).
    $expr: {
      $and: [
        { $eq: ['$total', { $sum: '$lineas.subtotal' }] },
        { $eq: ['$cantidad_items', { $sum: '$lineas.cantidad' }] },
        { $eq: [{ $size: '$lineas' }, { $size: { $setUnion: ['$lineas.id_producto', []] } }] },
        { $allElementsTrue: [{ $map: { input: '$lineas', as: 'l', in: {
            $and: [
              { $gte: ['$$l.precio_unitario', NumberDecimal('0')] },
              { $eq: ['$$l.subtotal', { $multiply: ['$$l.cantidad', '$$l.precio_unitario'] }] }
            ] } } }] }
      ]
    }
  }
});

// Índices pensados para las consultas de 04_consultas.js.
db.pedidos.createIndex({ estado: 1, fecha: 1 }, { name: 'estado_fecha' });
db.pedidos.createIndex({ 'lineas.id_producto': 1 }, { name: 'lineas_producto' });   // índice multiclave
db.pedidos.createIndex({ 'cliente.id_cliente': 1, fecha: -1 }, { name: 'cliente_fecha' });

printjson({
  coleccion: 'pedidos',
  validador: Object.keys(db.getCollectionInfos({ name: 'pedidos' })[0].options.validator),
  indices: db.pedidos.getIndexes().map(i => i.name)
});
