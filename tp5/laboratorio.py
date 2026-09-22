"""TP5: copias nuevas, DDL reversible, planes completos y comprobaciones reales."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import statistics
import subprocess
import time

import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('fase', choices=['preparar', 'indice', 'vista', 'materializada',
                                   'unico', 'escritura', 'verificar'])
parser.add_argument('--sesion', type=Path, required=True)
parser.add_argument('--numero', type=int, choices=[1, 2, 3])
parser.add_argument('--pg-bin', type=Path, required=True)
parser.add_argument('--host', default='127.0.0.1')
parser.add_argument('--port', type=int, default=55432)
parser.add_argument('--user', default='postgres')
args = parser.parse_args()


def connect(db):
    c = psycopg.connect(host=args.host, port=args.port, user=args.user, dbname=db,
                         autocommit=True, options='-c statement_timeout=300000')
    print(c.execute('SELECT current_database(), current_user').fetchone(), flush=True)
    c.execute("SET TIME ZONE 'UTC'")
    return c


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, default=str), encoding='utf-8')


def statements(name):
    # Los SQL de esta práctica no contienen cuerpos de funciones ni ; en literales.
    text = re.sub(r'--[^\n]*', '', (ROOT/name).read_text(encoding='utf-8'))
    return [s.strip() for s in text.split(';') if s.strip()]


def backup(db, label):
    path = ROOT.parent/'backups'/(db+'_'+label+'.dump')
    path.parent.mkdir(exist_ok=True)
    subprocess.run([str(args.pg_bin/'pg_dump'), '-h', args.host, '-p', str(args.port),
                    '-U', args.user, '-Fc', '-f', str(path), db], check=True)
    return str(path.relative_to(ROOT.parent))


def model(c):
    return c.execute("""SELECT c.relname,a.attname,format_type(a.atttypid,a.atttypmod),
        a.attnotnull,pg_get_expr(d.adbin,d.adrelid),a.attidentity
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
        LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum
        WHERE n.nspname='public' AND c.relkind='r' ORDER BY c.relname,a.attnum""").fetchall() + c.execute("""
        SELECT r.relname, c.conname, pg_get_constraintdef(c.oid)
        FROM pg_constraint c JOIN pg_class r ON r.oid=c.conrelid
        JOIN pg_namespace n ON n.oid=r.relnamespace
        WHERE n.nspname='public' ORDER BY r.relname,c.conname""").fetchall() + c.execute("""
        SELECT c.relname,t.tgname,pg_get_triggerdef(t.oid),pg_get_functiondef(t.tgfoid)
        FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
        JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND NOT t.tgisinternal ORDER BY c.relname,t.tgname""").fetchall()


def measure(c, folder, name, query):
    c.execute('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+query).fetchall()
    plans = [c.execute('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+query).fetchone()[0][0]
             for _ in range(5)]
    text = '\n'.join(r[0] for r in c.execute('EXPLAIN (ANALYZE,BUFFERS) '+query))
    (folder/(name+'.txt')).write_text(text+'\n', encoding='utf-8')
    times = [p['Execution Time'] for p in plans]
    result = {'consulta': query, 'mediana_ms': statistics.median(times),
              'min_ms': min(times), 'max_ms': max(times), 'planes': plans}
    save(folder/(name+'.json'), result)
    print(name, {k:v for k,v in result.items() if k not in ('planes','consulta')}, flush=True)
    return {k:v for k,v in result.items() if k != 'planes'}


def compare(c, a, b):
    difference = c.execute(f"""WITH a AS ({a}), b AS ({b}) SELECT
        (SELECT count(*) FROM (TABLE a EXCEPT ALL TABLE b) x),
        (SELECT count(*) FROM (TABLE b EXCEPT ALL TABLE a) x)""").fetchone()
    assert difference == (0, 0), difference
    rows = c.execute(a).fetchall()
    assert rows == c.execute(b).fetchall(), 'Diferencias de orden/valores'
    result = {'diferencias': difference, 'filas': len(rows), 'orden_igual': True,
              'muestra': rows[:3]}
    print('Equivalencia:', result, flush=True)
    return result


def safe_ddl(c, s, label, statement, check):
    s.setdefault('respaldos', {})[label] = backup(s['base'], label)
    c.execute('BEGIN')
    try:
        status = c.execute(statement).statusmessage
        result = check()
        print(label, status, result, 'ROLLBACK', flush=True)
    finally:
        c.execute('ROLLBACK')
    c.execute('BEGIN')
    try:
        status = c.execute(statement).statusmessage
        result = check()
        c.execute('COMMIT')
    except BaseException:
        c.execute('ROLLBACK')
        raise
    print(label, status, result, 'COMMIT', flush=True)
    s.setdefault('ddl', {})[label] = {'sentencia': statement, 'estado': status,
                                    'ensayo_revertido': True, 'verificacion': result}


def prepare():
    source = json.loads(args.sesion.read_text(encoding='utf-8'))['base']
    if not re.fullmatch(r'food_store_tp4_\d{8}_\d{6}', source):
        raise ValueError('Indicar sesion del TP4; no se aceptan bases de producción')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
    baseline, work = 'food_store_tp5_'+stamp+'_antes', 'food_store_tp5_'+stamp
    folder = ROOT/'evidencias'/stamp
    folder.mkdir(parents=True)
    with connect('postgres') as c:
        c.execute(sql.SQL('CREATE DATABASE {} TEMPLATE {}').format(
            sql.Identifier(baseline), sql.Identifier(source)))
    with connect(baseline) as c:
        s = {'base': work, 'base_antes': baseline, 'fuente': source, 'estado': 'preparado',
             'version': c.execute('SELECT version()').fetchone()[0], 'mediciones': {}}
        s['respaldo_inicial'] = backup(baseline, 'inicial')
        s['modelo_inicial'] = model(c)
        s['conteos_heredados'] = c.execute('SELECT (SELECT count(*) FROM producto),'
            '(SELECT count(*) FROM cliente),(SELECT count(*) FROM pedido),'
            '(SELECT count(*) FROM detalle_pedido)').fetchone()
        assert s['conteos_heredados'] == (50003, 20001, 200003, 600000)
        # Un pedido de laboratorio vacío, clonado idéntico a ambas variantes.
        insert = """INSERT INTO pedido(fecha,estado,forma_pago,cliente_id)
            SELECT TIMESTAMPTZ '2026-09-22 00:00:00+00','PENDIENTE','EFECTIVO',min(id_cliente)
            FROM cliente RETURNING id_pedido"""
        c.execute('BEGIN')
        print('Pedido de prueba revertido:', c.execute(insert).fetchone(), flush=True)
        c.execute('ROLLBACK')
        s['pedido_escritura'] = c.execute(insert).fetchone()[0]
        s['productos_escritura'] = c.execute('SELECT id_producto,precio_lista FROM producto '
            'WHERE activo AND stock>=1 ORDER BY id_producto LIMIT 800').fetchall()
        assert len(s['productos_escritura']) == 800
        c.execute('VACUUM (ANALYZE)')
        s['indices_iniciales'] = c.execute("SELECT tablename,indexname,indexdef FROM pg_indexes "
            "WHERE schemaname='public' ORDER BY tablename,indexname").fetchall()
        s['configuracion'] = c.execute("SELECT name,setting FROM pg_settings WHERE name IN "
            "('work_mem','shared_buffers','random_page_cost','seq_page_cost',"
            "'max_parallel_workers_per_gather','jit') ORDER BY name").fetchall()
    with connect('postgres') as c:
        c.execute(sql.SQL('CREATE DATABASE {} TEMPLATE {}').format(
            sql.Identifier(work), sql.Identifier(baseline)))
    save(folder/'sesion.json', s)
    print('SESION', folder/'sesion.json', flush=True)


def index(c, s):
    n = args.numero
    if n is None: raise ValueError('Falta --numero')
    q = statements('queries.sql')[n-1]
    rows = c.execute(q).fetchall()
    label = 'i'+str(n)
    s['mediciones'][label+'_antes'] = measure(c, args.sesion.parent, label+'_antes', q)
    def check():
        assert c.execute(q).fetchall() == rows
        return {'filas_iguales': len(rows)}
    safe_ddl(c, s, label, statements('indices.sql')[n-1], check)
    s['mediciones'][label+'_despues'] = measure(c, args.sesion.parent, label+'_despues', q)


VIEW_NAMES = ['tp5_productos_vigentes','tp5_pedidos_clientes','tp5_detalles_productos']
VIEW_ORDERS = ['id_producto','id_pedido','id_pedido,id_producto']


def view_check(c, n):
    return compare(c, 'SELECT * FROM '+VIEW_NAMES[n-1]+' ORDER BY '+VIEW_ORDERS[n-1],
                   statements('referencias_vistas.sql')[n-1])


def view(c, s):
    n = args.numero
    if n is None: raise ValueError('Falta --numero')
    safe_ddl(c, s, 'v'+str(n), statements('views.sql')[n-1], lambda: view_check(c, n))


def materialized(c, s):
    original = statements('reporte_original.sql')[0]
    consumer = 'SELECT * FROM tp5_facturacion_mensual ORDER BY mes,id_categoria'
    safe_ddl(c, s, 'materializada', statements('materializadas.sql')[0],
             lambda: compare(c, consumer, original))
    s['mediciones']['reporte_original'] = measure(c,args.sesion.parent,'reporte_original',original)
    s['mediciones']['reporte_materializado'] = measure(c,args.sesion.parent,'reporte_materializado',consumer)


def unique(c, s):
    def check():
        started = time.perf_counter()
        status = c.execute('REFRESH MATERIALIZED VIEW CONCURRENTLY tp5_facturacion_mensual').statusmessage
        elapsed = (time.perf_counter()-started)*1000
        return {'estado': status, 'duracion_ms': elapsed,
                'equivalencia': compare(c, 'SELECT * FROM tp5_facturacion_mensual ORDER BY mes,id_categoria',
                                       statements('reporte_original.sql')[0])}
    safe_ddl(c, s, 'unico_materializada', statements('materializadas.sql')[1], check)


def write_trial(c, s, batch):
    c.execute('BEGIN')
    try:
        before = c.execute('SELECT count(*) FROM detalle_pedido WHERE id_pedido=%s',
                           (s['pedido_escritura'],)).fetchone()[0]
        assert before == 0
        started = time.perf_counter()
        if batch:
            query = """INSERT INTO detalle_pedido(id_pedido,id_producto,precio_unitario,cantidad)
                SELECT %s,id_producto,precio_lista,1 FROM producto
                WHERE activo AND stock>=1 ORDER BY id_producto LIMIT 800"""
            plan = c.execute('EXPLAIN (ANALYZE,BUFFERS,WAL,FORMAT JSON) '+query,
                             (s['pedido_escritura'],)).fetchone()[0][0]
            result = {'ms': plan['Execution Time'], 'plan': plan}
        else:
            for product, price in s['productos_escritura']:
                c.execute('INSERT INTO detalle_pedido VALUES (%s,%s,%s,1)',
                          (s['pedido_escritura'], product, price))
            result = {'ms': (time.perf_counter()-started)*1000}
        assert c.execute('SELECT count(*) FROM detalle_pedido WHERE id_pedido=%s',
                         (s['pedido_escritura'],)).fetchone()[0] == 800
        result['filas'] = 800
    finally:
        c.execute('ROLLBACK')
    assert c.execute('SELECT count(*) FROM detalle_pedido WHERE id_pedido=%s',
                     (s['pedido_escritura'],)).fetchone()[0] == 0
    return result


def writing(s):
    result = {'metodo': 'Un calentamiento y siete pares alternados. Cada carga se revierte.',
              'individuales': {'antes': [], 'despues': []}, 'lote': {'antes': [], 'despues': []}}
    with connect(s['base_antes']) as before, connect(s['base']) as after:
        for c in (before,after):
            c.execute('VACUUM (ANALYZE) detalle_pedido')
            write_trial(c,s,False)
            write_trial(c,s,True)
        for i in range(7):
            pair = [('antes',before),('despues',after)]
            if i%2: pair.reverse()
            for label,c in pair:
                result['individuales'][label].append(write_trial(c,s,False))
                result['lote'][label].append(write_trial(c,s,True))
        for mode in ('individuales','lote'):
            result[mode]['resumen'] = {label: {
                'mediana_ms': statistics.median(r['ms'] for r in result[mode][label]),
                'min_ms': min(r['ms'] for r in result[mode][label]),
                'max_ms': max(r['ms'] for r in result[mode][label])}
                for label in ('antes','despues')}
            print('Escritura', mode, result[mode]['resumen'], flush=True)
    save(args.sesion.parent/'escritura.json',result)
    s['escritura'] = {k:result[k]['resumen'] for k in ('individuales','lote')}


def verify(c, s):
    s['respaldos']['verificaciones'] = backup(s['base'],'verificaciones')
    s['vistas_base'] = {name:view_check(c,i) for i,name in enumerate(VIEW_NAMES,1)}
    role = 'tp5_reportes_'+s['base'].removeprefix('food_store_tp5_')
    counts_before = c.execute('SELECT (SELECT count(*) FROM categoria),'
        '(SELECT count(*) FROM producto),(SELECT count(*) FROM pedido),'
        '(SELECT count(*) FROM detalle_pedido)').fetchone()
    original = statements('reporte_original.sql')[0]
    consumer = 'SELECT * FROM tp5_facturacion_mensual ORDER BY mes,id_categoria'
    snapshot = c.execute(consumer).fetchall()
    c.execute('BEGIN')
    try:
        # El rol y sus GRANT existen solo dentro de la transacción de prueba.
        c.execute(sql.SQL('CREATE ROLE {} NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT').format(sql.Identifier(role)))
        c.execute(sql.SQL('GRANT USAGE ON SCHEMA public TO {}').format(sql.Identifier(role)))
        c.execute(sql.SQL('GRANT SELECT ON tp5_pedidos_clientes TO {}').format(sql.Identifier(role)))
        c.execute(sql.SQL('SET LOCAL ROLE {}').format(sql.Identifier(role)))
        identity = c.execute('SELECT current_user').fetchone()[0]
        assert identity == role
        visible = c.execute('SELECT count(*) FROM tp5_pedidos_clientes').fetchone()[0]
        denied = []
        for query,code in [('SELECT * FROM cliente LIMIT 1','42501'),
                           ('SELECT * FROM pedido LIMIT 1','42501'),
                           ('SELECT correo_electronico FROM tp5_pedidos_clientes','42703'),
                           ('SELECT nro_telefono FROM tp5_pedidos_clientes','42703')]:
            c.execute('SAVEPOINT permiso')
            try:
                c.execute(query)
            except psycopg.Error as error:
                assert error.sqlstate == code, error
                denied.append({'consulta':query,'sqlstate':error.sqlstate})
                c.execute('ROLLBACK TO SAVEPOINT permiso')
            else:
                raise AssertionError('Se permitió un acceso que debía fallar: '+query)
            c.execute('RELEASE SAVEPOINT permiso')
        c.execute('RESET ROLE')
        s['seguridad'] = {'rol':identity,'filas_visibles':visible,'rechazos':denied}
        print('Seguridad',s['seguridad'],flush=True)

        active_cat = c.execute("INSERT INTO categoria(nombre,activo) VALUES ('TP5 borde activa',true) RETURNING id_categoria").fetchone()[0]
        inactive_cat = c.execute("INSERT INTO categoria(nombre,activo) VALUES ('TP5 borde inactiva',false) RETURNING id_categoria").fetchone()[0]
        products = []
        for name,category in [('vigente',active_cat),('categoria inactiva',inactive_cat),('baja posterior',active_cat)]:
            products.append(c.execute('INSERT INTO producto(nombre,precio_lista,stock,activo,categoria_id) '
                'VALUES (%s,100,10,true,%s) RETURNING id_producto',('TP5 borde '+name,category)).fetchone()[0])
        client = c.execute('SELECT min(id_cliente) FROM cliente').fetchone()[0]
        orders = [c.execute("INSERT INTO pedido(fecha,estado,forma_pago,cliente_id) "
            "VALUES ('2025-06-15 00:00:00+00','PENDIENTE','EFECTIVO',%s) RETURNING id_pedido",(client,)).fetchone()[0]
            for _ in range(3)]
        for product in products:
            c.execute('INSERT INTO detalle_pedido VALUES (%s,%s,17,2)',(orders[0],product))
        c.execute('INSERT INTO detalle_pedido VALUES (%s,%s,8,1)',(orders[1],products[0]))
        c.execute("UPDATE pedido SET estado='CONFIRMADO' WHERE id_pedido=%s",(orders[0],))
        c.execute("UPDATE pedido SET estado='ENTREGADO' WHERE id_pedido=%s",(orders[0],))
        c.execute("UPDATE pedido SET estado='CANCELADO' WHERE id_pedido=%s",(orders[1],))
        c.execute('UPDATE producto SET activo=false WHERE id_producto=%s',(products[2],))
        assert c.execute('SELECT id_producto FROM tp5_productos_vigentes WHERE id_producto=ANY(%s)',(products,)).fetchall() == [(products[0],)]
        assert c.execute('SELECT estado FROM tp5_pedidos_clientes WHERE id_pedido=ANY(%s) ORDER BY id_pedido',(orders,)).fetchall() == [('ENTREGADO',),('CANCELADO',),('PENDIENTE',)]
        details = c.execute('SELECT subtotal FROM tp5_detalles_productos WHERE id_pedido=ANY(%s) '
                            'ORDER BY id_pedido,id_producto',(orders,)).fetchall()
        assert details == [(34,),(34,),(34,),(8,)],details
        assert c.execute('SELECT count(*) FROM tp5_detalles_productos WHERE id_pedido=%s',(orders[2],)).fetchone()[0] == 0
        s['vistas_con_bordes'] = {name:view_check(c,i) for i,name in enumerate(VIEW_NAMES,1)}
        s['bordes'] = {'categoria_activa':active_cat,'categoria_inactiva':inactive_cat,
            'productos':products,'pedidos':orders,'subtotales_historicos':details,
            'solo_producto_vigente_visible':True,'tres_estados_conservados':True,
            'pedido_sin_lineas':0}
        # Venta entregada válida: solo el producto vigente aporta 2*17 a la MV.
        assert c.execute(consumer).fetchall() == snapshot, 'La MV se actualizó sin REFRESH'
        amount = c.execute('SELECT importe FROM ('+original+') q WHERE id_categoria=%s',
                           (active_cat,)).fetchone()[0]
        assert amount == 34
        started = time.perf_counter()
        refresh = c.execute('REFRESH MATERIALIZED VIEW CONCURRENTLY tp5_facturacion_mensual').statusmessage
        elapsed = (time.perf_counter()-started)*1000
        assert c.execute('SELECT importe FROM tp5_facturacion_mensual WHERE id_categoria=%s',
                         (active_cat,)).fetchone()[0] == 34
        s['frescura'] = {'sin_refresh_conserva_snapshot':True,'venta_nueva_importe':amount,
            'refresh':refresh,'duracion_ms':elapsed,'despues':compare(c,consumer,original)}
        print('Frescura',s['frescura'],flush=True)
    finally:
        c.execute('ROLLBACK')
    assert c.execute('SELECT count(*) FROM pg_roles WHERE rolname=%s',(role,)).fetchone()[0] == 0
    assert c.execute(consumer).fetchall() == snapshot
    assert c.execute('SELECT (SELECT count(*) FROM categoria),(SELECT count(*) FROM producto),'
        '(SELECT count(*) FROM pedido),(SELECT count(*) FROM detalle_pedido)').fetchone() == counts_before
    s['bordes_y_permisos_revertidos'] = True
    s['conteos_finales_categoria_producto_pedido_detalle'] = counts_before
    s['tamano_objetos'] = c.execute("SELECT c.relname,pg_relation_size(c.oid) FROM pg_class c "
        "JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' "
        "AND c.relname LIKE 'tp5_%' AND c.relkind IN ('i','m') ORDER BY c.relname").fetchall()
    s['indices_finales'] = c.execute("SELECT tablename,indexname,indexdef FROM pg_indexes "
        "WHERE schemaname='public' ORDER BY tablename,indexname").fetchall()
    # Comparación normalizada porque la sesión JSON transforma las tuplas en listas.
    assert json.loads(json.dumps(model(c),default=str)) == s['modelo_inicial'], 'Modelo alterado'
    s['modelo_sin_cambios'] = True
    s['estado'] = 'verificado'
    print('Modelo base, restricciones y triggers sin cambios', flush=True)


if __name__ == '__main__':
    if args.fase == 'preparar':
        prepare()
    else:
        s = json.loads(args.sesion.read_text(encoding='utf-8'))
        if not re.fullmatch(r'food_store_tp5_\d{8}_\d{6}',s['base']):
            raise ValueError('Usar sesión propia del TP5')
        if args.fase == 'escritura':
            writing(s)
        else:
            with connect(s['base']) as c:
                {'indice': index, 'vista': view, 'materializada': materialized,
                 'unico': unique, 'verificar': verify}[args.fase](c,s)
        save(args.sesion,s)
