"""Instala el TPI desde cero en una base nueva y conserva evidencia real de sus pruebas."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import time

import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
parser = argparse.ArgumentParser()
parser.add_argument('--pg-bin', type=Path, required=True)
parser.add_argument('--host', default='127.0.0.1')
parser.add_argument('--port', type=int, default=55432)
parser.add_argument('--user', default='postgres')
args = parser.parse_args()
stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
DB = 'food_store_tpi_'+stamp
FOLDER = ROOT/'evidencias'/stamp
FOLDER.mkdir(parents=True)
RESULT = {'base':DB,'exito':False,'eventos':[],'pruebas':[],'respaldos':[]}


def query(c, statement, params=None):
    cur = c.execute(statement, params)
    outputs = []
    while True:
        outputs.append({'estado':cur.statusmessage,
                        'filas':cur.fetchall() if cur.description else None})
        if not cur.nextset(): break
    RESULT['eventos'].append({'sql':statement,'parametros':params,'salida':outputs})
    return outputs[0]['filas']


def scalar(c, statement, params=None):
    return query(c,statement,params)[0][0]


def check(name, condition, detail=None):
    RESULT['pruebas'].append({'prueba':name,'correcto':bool(condition),'detalle':detail})
    if not condition: raise AssertionError((name,detail))
    print('OK',name,detail if detail is not None else '',flush=True)


def connect(name=DB):
    c = psycopg.connect(host=args.host,port=args.port,user=args.user,dbname=name,
                         autocommit=True,options='-c statement_timeout=60000 -c lock_timeout=10000')
    query(c,'SELECT current_database(),current_user,version()')
    query(c,"SET TIME ZONE 'UTC'")
    return c


def backup(label):
    target = REPO/'backups'/(DB+'_'+label+'.dump')
    target.parent.mkdir(exist_ok=True)
    subprocess.run([str(args.pg_bin/'pg_dump'),'-h',args.host,'-p',str(args.port),
                    '-U',args.user,'-Fc','-f',str(target),DB],check=True)
    RESULT['respaldos'].append(str(target.relative_to(REPO)))


def scripts(c, names):
    for name in names:
        query(c,(REPO/name).read_text(encoding='utf-8-sig'))


def expected(c, name, code, statement, params=None):
    query(c,'SAVEPOINT error_esperado')
    try:
        query(c,statement,params)
    except psycopg.Error as error:
        RESULT['eventos'].append({'sql':statement,'parametros':params,'sqlstate':error.sqlstate,
                                  'error':str(error)})
        query(c,'ROLLBACK TO SAVEPOINT error_esperado')
        check(name,error.sqlstate == code,{'esperado':code,'obtenido':error.sqlstate})
    else:
        raise AssertionError('No se rechazó: '+name)
    finally:
        query(c,'RELEASE SAVEPOINT error_esperado')


CALL = 'CALL public.tpi_registrar_pedido(%s,%s::forma_pago,%s::jsonb,NULL)'


def order(c, products, quantities=(2,1)):
    lines = [{'id_producto':p,'cantidad':n} for p,n in zip(products,quantities)]
    return scalar(c,CALL,(1,'EFECTIVO',json.dumps(lines)))


def fixture(c, label):
    cats = [scalar(c,'INSERT INTO categoria(nombre) VALUES (%s) RETURNING id_categoria',
                   ('TPI '+label+' '+str(i),)) for i in range(2)]
    products = [scalar(c,'INSERT INTO producto(nombre,precio_lista,stock,categoria_id) '
        'VALUES (%s,%s,%s,%s) RETURNING id_producto',
        ('TPI '+label+' producto '+str(i),price,stock,cat))
        for i,(price,stock,cat) in enumerate(zip([10,25],[10,2],cats))]
    return cats,products


def core(c, label):
    cats,products = fixture(c,label)
    oid = order(c,products)
    check(label+' total exacto',scalar(c,'SELECT tpi_total_pedido(%s)',(oid,)) == 45)
    check(label+' dos detalles',scalar(c,'SELECT count(*) FROM detalle_pedido WHERE id_pedido=%s',(oid,)) == 2)
    check(label+' pedido vacío',scalar(c,'SELECT tpi_total_pedido(1)') == 0)
    expected(c,label+' total inexistente','P0002','SELECT tpi_total_pedido(-1)')
    counts = query(c,'SELECT (SELECT count(*) FROM pedido),(SELECT count(*) FROM detalle_pedido)')
    expected(c,label+' fallo en segunda línea revierte CALL','23514',CALL,
             (1,'EFECTIVO',json.dumps([{'id_producto':products[0],'cantidad':1},
                                      {'id_producto':products[1],'cantidad':3}])))
    check(label+' sin cabecera ni detalle parcial',query(c,'SELECT (SELECT count(*) FROM pedido),'
          '(SELECT count(*) FROM detalle_pedido)') == counts)
    query(c,'CALL tpi_baja_producto(%s)',(products[0],))
    check(label+' baja conserva total',scalar(c,'SELECT tpi_total_pedido(%s)',(oid,)) == 45)
    expected(c,label+' venta de producto inactivo','23514',CALL,
             (1,'EFECTIVO',json.dumps([{'id_producto':products[0],'cantidad':1}])))
    query(c,'UPDATE categoria SET activo=false WHERE id_categoria=%s',(cats[1],))
    expected(c,label+' transición UPDATE rechaza categoría inactiva','23514',
             'UPDATE detalle_pedido SET precio_unitario=precio_unitario+1 WHERE id_pedido=%s',(oid,))
    check(label+' UPDATE múltiple revertido',scalar(c,'SELECT tpi_total_pedido(%s)',(oid,)) == 45)


def install(c):
    base = ['schema.sql','restricciones_Food_Store.sql','datos_iniciales.sql',
            'tp3/indices.sql','tp4/indices.sql','tp5/indices.sql','tp5/views.sql','tp5/materializadas.sql']
    backup('base_pre_ddl')
    for end in ['ROLLBACK','COMMIT']:
        query(c,'BEGIN')
        try:
            scripts(c,base)
            check('instalación base '+end,scalar(c,"SELECT count(*) FROM pg_tables WHERE schemaname='public'") == 5)
            query(c,end)
        except BaseException:
            query(c,'ROLLBACK')
            raise
    # Volumen pequeño para observar el uso del índice parcial sin forzar al planificador.
    load = """INSERT INTO producto(nombre,precio_lista,stock,categoria_id)
        SELECT 'TPI volumen '||g,10,10,1 FROM generate_series(1,4000) s(g)"""
    query(c,'BEGIN')
    query(c,load)
    check('carga auxiliar reversible',scalar(c,'SELECT count(*) FROM producto') == 4003)
    query(c,'ROLLBACK')
    query(c,load)
    query(c,'VACUUM (ANALYZE)')
    additions = ['tpi/funciones.sql','tpi/registrar_pedido.sql','tpi/baja_producto.sql',
                 'tpi/categorias_transicion.sql']
    backup('objetos_pre_ddl')
    query(c,'BEGIN')
    try:
        scripts(c,additions)
        core(c,'ensayo DDL')
    finally:
        query(c,'ROLLBACK')
    check('DDL de ensayo desapareció',scalar(c,"SELECT count(*) FROM pg_proc WHERE proname LIKE 'tpi_%'") == 0)
    query(c,'BEGIN')
    try:
        scripts(c,additions)
        check('cuatro rutinas creadas',scalar(c,"SELECT count(*) FROM pg_proc WHERE proname LIKE 'tpi_%'") == 4)
        query(c,'COMMIT')
    except BaseException:
        query(c,'ROLLBACK')
        raise


def cases(c):
    query(c,'BEGIN')
    try:
        core(c,'prueba final')
        invalid = [None,{},[],[1],[{'id_producto':1}],
            [{'id_producto':1,'cantidad':0}],[{'id_producto':1,'cantidad':1.5}],
            [{'id_producto':True,'cantidad':1}],[{'id_producto':1,'cantidad':'2'}],
            [{'id_producto':1,'cantidad':1,'precio':0}],
            [{'id_producto':1,'cantidad':2147483648}],
            [{'id_producto':1,'cantidad':1},{'id_producto':1,'cantidad':2}]]
        for i,payload in enumerate(invalid):
            expected(c,'JSON inválido '+str(i),'22023',CALL,(1,'EFECTIVO',json.dumps(payload)))
        expected(c,'cliente inexistente','23503',CALL,(-1,'EFECTIVO','[{"id_producto":1,"cantidad":1}]'))
        expected(c,'producto inexistente','23503',CALL,(1,'EFECTIVO','[{"id_producto":2147483647,"cantidad":1}]'))
        expected(c,'pago nulo','23502',CALL,(1,None,'[{"id_producto":1,"cantidad":1}]'))
        expected(c,'salida no nula','22023','CALL tpi_registrar_pedido(1,\'EFECTIVO\',\'[]\',42)')
        expected(c,'baja inexistente','P0002','CALL tpi_baja_producto(-1)')
        expected(c,'total con NULL','P0002','SELECT tpi_total_pedido(NULL)')
        expected(c,'CHECK stock','23514','UPDATE producto SET stock=-1 WHERE id_producto=1')
        expected(c,'CHECK precio','23514','UPDATE producto SET precio_lista=-1 WHERE id_producto=1')
        expected(c,'FK categoría','23503','UPDATE producto SET categoria_id=-1 WHERE id_producto=1')
        expected(c,'CHECK cantidad','23514','INSERT INTO detalle_pedido VALUES (1,1,10,0)')
        expected(c,'CHECK precio de venta','23514','INSERT INTO detalle_pedido VALUES (1,1,-1,1)')
        expected(c,'transición de estado inválida','23514',"UPDATE pedido SET estado='ENTREGADO' WHERE id_pedido=1")
        query(c,"UPDATE pedido SET estado='CONFIRMADO' WHERE id_pedido=1")
        expected(c,'detalle de pedido confirmado','23514','INSERT INTO detalle_pedido VALUES (1,1,10,1)')
        query(c,"UPDATE pedido SET estado='ENTREGADO' WHERE id_pedido=1")
        expected(c,'salida de estado terminal','23514',"UPDATE pedido SET estado='CANCELADO' WHERE id_pedido=1")
    finally:
        query(c,'ROLLBACK')


def plan(c, label, name):
    statement = 'SELECT id_producto,nombre FROM producto WHERE activo AND lower(nombre)=lower(%s)'
    result = scalar(c,'EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+statement,(name,))
    RESULT.setdefault('planes_baja',{})[label] = result
    return query(c,statement,(name,))


def soft_delete(c):
    query(c,'BEGIN')
    try:
        cats,products = fixture(c,'baja lógica')
        oid = order(c,products)
        name = scalar(c,'SELECT nombre FROM producto WHERE id_producto=%s',(products[0],))
        check('índice parcial antes devuelve producto',len(plan(c,'antes',name)) == 1)
        old = query(c,'SELECT * FROM tp5_detalles_productos WHERE id_pedido=%s ORDER BY id_producto',(oid,))
        query(c,'UPDATE producto SET precio_lista=999 WHERE id_producto=%s',(products[0],))
        query(c,'CALL tpi_baja_producto(%s)',(products[0],))
        query(c,'CALL tpi_baja_producto(%s)',(products[0],))
        check('baja idempotente conserva fila',scalar(c,'SELECT activo FROM producto WHERE id_producto=%s',(products[0],)) is False)
        check('índice parcial después no devuelve producto',plan(c,'despues',name) == [])
        check('vista de catálogo excluye baja',scalar(c,'SELECT count(*) FROM tp5_productos_vigentes WHERE id_producto=%s',(products[0],)) == 0)
        check('historia y precio de venta intactos',query(c,'SELECT * FROM tp5_detalles_productos WHERE id_pedido=%s ORDER BY id_producto',(oid,)) == old)
        check('función conserva total histórico',scalar(c,'SELECT tpi_total_pedido(%s)',(oid,)) == 45)
        expected(c,'UNIQUE conserva nombre tras baja','23505',
                 'INSERT INTO producto(nombre,precio_lista,stock,categoria_id) VALUES (%s,1,1,%s)',(name,cats[0]))
        expected(c,'FK impide borrar producto usado','23503','DELETE FROM producto WHERE id_producto=%s',(products[0],))
        query(c,'UPDATE categoria SET activo=false WHERE id_categoria=%s',(cats[1],))
        check('baja de categoría oculta producto aún activo',scalar(c,'SELECT count(*) FROM tp5_productos_vigentes WHERE id_producto=%s',(products[1],)) == 0)
        check('categoría inactiva mantiene historial',scalar(c,'SELECT tpi_total_pedido(%s)',(oid,)) == 45)
        expected(c,'CALL rechaza categoría inactiva','23514',CALL,
                 (1,'EFECTIVO',json.dumps([{'id_producto':products[1],'cantidad':1}])))
        # Dos productos activos: el rechazo debe provenir de la transición de categoría.
        query(c,'UPDATE producto SET activo=true WHERE id_producto=%s',(products[0],))
        empty = scalar(c,"INSERT INTO pedido(cliente_id,forma_pago) VALUES (1,'EFECTIVO') RETURNING id_pedido")
        expected(c,'INSERT múltiple atómico por categoría','23514',
                 'INSERT INTO detalle_pedido VALUES (%s,%s,10,1),(%s,%s,25,1)',
                 (empty,products[0],empty,products[1]))
        check('INSERT múltiple no deja primera fila',scalar(c,'SELECT count(*) FROM detalle_pedido WHERE id_pedido=%s',(empty,)) == 0)
        query(c,'UPDATE categoria SET activo=true WHERE id_categoria=%s',(cats[1],))
        query(c,'INSERT INTO detalle_pedido VALUES (%s,%s,10,1),(%s,%s,25,1)',(empty,products[0],empty,products[1]))
        check('INSERT múltiple válido',scalar(c,'SELECT count(*) FROM detalle_pedido WHERE id_pedido=%s',(empty,)) == 2)
        query(c,'UPDATE detalle_pedido SET cantidad=2 WHERE id_pedido=%s',(empty,))
        check('UPDATE múltiple válido',scalar(c,'SELECT tpi_total_pedido(%s)',(empty,)) == 70)
        query(c,'UPDATE categoria SET activo=false WHERE id_categoria=%s',(cats[1],))
        expected(c,'UPDATE múltiple rechazado completo','23514',
                 'UPDATE detalle_pedido SET precio_unitario=0 WHERE id_pedido=%s',(empty,))
        check('UPDATE conserva ambos precios',scalar(c,'SELECT tpi_total_pedido(%s)',(empty,)) == 70)
    finally:
        query(c,'ROLLBACK')


def transaction_and_concurrency(c):
    query(c,'BEGIN')
    cats,products = fixture(c,'transacciones')
    query(c,'COMMIT')
    with connect() as observer, connect() as worker:
        query(c,'BEGIN')
        oid = order(c,products)
        check('otra conexión no ve pedido sin COMMIT',scalar(observer,'SELECT count(*) FROM pedido WHERE id_pedido=%s',(oid,)) == 0)
        query(c,'COMMIT')
        check('otra conexión ve pedido tras COMMIT',scalar(observer,'SELECT tpi_total_pedido(%s)',(oid,)) == 45)
        query(c,'BEGIN')
        rolled = order(c,products)
        query(c,'ROLLBACK')
        check('ROLLBACK elimina cabecera y detalles',query(observer,'SELECT (SELECT count(*) FROM pedido WHERE id_pedido=%s),'
              '(SELECT count(*) FROM detalle_pedido WHERE id_pedido=%s)',(rolled,rolled)) == [(0,0)])
        initial = scalar(c,'SELECT count(*) FROM pedido')
        pid = scalar(worker,'SELECT pg_backend_pid()')
        query(c,'BEGIN')
        query(c,'UPDATE categoria SET activo=false WHERE id_categoria=%s',(cats[0],))
        def waiting_sale():
            query(worker,'BEGIN')
            try:
                expected(worker,'venta concurrente rechazada tras baja','23514',CALL,
                         (1,'EFECTIVO',json.dumps([{'id_producto':products[0],'cantidad':1}])))
            finally:
                query(worker,'ROLLBACK')
        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(waiting_sale)
            try:
                deadline = time.monotonic()+5
                blocked = False
                while time.monotonic()<deadline:
                    blockers = scalar(observer,'SELECT pg_blocking_pids(%s)',(pid,))
                    if blockers:
                        blocked = True
                        break
                    if future.done(): break
                    time.sleep(0.05)
                check('bloqueo real ante baja de categoría',blocked,{'pid_venta':pid,'bloqueadores':blockers})
                query(c,'COMMIT')
                future.result(timeout=15)
            finally:
                if c.info.transaction_status != psycopg.pq.TransactionStatus.IDLE:
                    query(c,'ROLLBACK')
        check('concurrencia sin pedido parcial',scalar(c,'SELECT count(*) FROM pedido') == initial)
        query(c,'UPDATE categoria SET activo=true WHERE id_categoria=%s',(cats[0],))
        RESULT['pedido_confirmado_por_commit'] = oid
        RESULT['productos_transacciones'] = products
        # Un entregado para validar la materializada y las consultas integradoras.
        query(c,"UPDATE pedido SET estado='CONFIRMADO' WHERE id_pedido=%s",(oid,))
        query(c,"UPDATE pedido SET estado='ENTREGADO' WHERE id_pedido=%s",(oid,))
        query(c,'REFRESH MATERIALIZED VIEW CONCURRENTLY tp5_facturacion_mensual')
        check('materializada refleja venta entregada',scalar(c,'SELECT sum(importe) FROM tp5_facturacion_mensual') == 45)


def equivalence(c):
    for name in ['productos_vigentes','pedidos_clientes','detalles_productos']:
        # La referencia es un SQL escrito sobre tablas, no la definición de la vista.
        import re
        refs = re.sub(r'--[^\n]*','',(REPO/'tp5/referencias_vistas.sql').read_text(encoding='utf-8'))
        refs = [s.strip() for s in refs.split(';') if s.strip()]
        i = ['productos_vigentes','pedidos_clientes','detalles_productos'].index(name)
        diff = query(c,'WITH a AS (SELECT * FROM tp5_'+name+'), b AS ('+refs[i]+') '
                     'SELECT (SELECT count(*) FROM (TABLE a EXCEPT ALL TABLE b) x),'
                     '(SELECT count(*) FROM (TABLE b EXCEPT ALL TABLE a) x)')
        check('vista '+name+' equivalente',diff == [(0,0)],diff)


def main():
    with connect('postgres') as admin:
        query(admin,sql.SQL('CREATE DATABASE {}').format(sql.Identifier(DB)).as_string(admin))
    with connect() as c:
        RESULT['version'] = scalar(c,'SHOW server_version')
        install(c)
        baseline = query(c,'SELECT (SELECT count(*) FROM categoria),(SELECT count(*) FROM producto),'
                         '(SELECT count(*) FROM pedido),(SELECT count(*) FROM detalle_pedido)')
        cases(c)
        soft_delete(c)
        check('casos revertidos y conteos restaurados',query(c,'SELECT (SELECT count(*) FROM categoria),'
              '(SELECT count(*) FROM producto),(SELECT count(*) FROM pedido),'
              '(SELECT count(*) FROM detalle_pedido)') == baseline)
        transaction_and_concurrency(c)
        equivalence(c)
        RESULT['rutinas'] = query(c,"SELECT p.proname,p.prokind,l.lanname,pg_get_function_identity_arguments(p.oid) "
            "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang "
            "WHERE n.nspname='public' ORDER BY p.proname")
        RESULT['triggers'] = query(c,"SELECT tgname,pg_get_triggerdef(oid) FROM pg_trigger "
            "WHERE NOT tgisinternal ORDER BY tgname")
        RESULT['conteos_finales'] = query(c,'SELECT (SELECT count(*) FROM categoria),'
              '(SELECT count(*) FROM producto),(SELECT count(*) FROM cliente),'
              '(SELECT count(*) FROM pedido),(SELECT count(*) FROM detalle_pedido)')[0]
    RESULT['exito'] = True
    print('TPI VERIFICADO:',len(RESULT['pruebas']),'comprobaciones; evidencia:',FOLDER,flush=True)


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        RESULT['error_final'] = repr(error)
        raise
    finally:
        (FOLDER/'resultado.json').write_text(json.dumps(RESULT,indent=2,ensure_ascii=False,default=str),encoding='utf-8')
