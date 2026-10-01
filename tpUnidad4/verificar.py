"""Unidad 4: base independiente, pruebas reversibles y mediciones reales."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import statistics
import subprocess
import time
import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
parser = argparse.ArgumentParser()
parser.add_argument('--pg-bin', type=Path, required=True)
parser.add_argument('--host', default='127.0.0.1')
parser.add_argument('--port', type=int, default=5432)
parser.add_argument('--user', default='postgres')
args = parser.parse_args()
stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
DB = 'food_store_u4_' + stamp
OUT = ROOT/'evidencias'/stamp
OUT.mkdir(parents=True)
R = {'base': DB, 'exito': False, 'pruebas': [], 'eventos': [], 'mediciones': {}}

def connect(db=DB):
    c = psycopg.connect(host=args.host, port=args.port, user=args.user,
        dbname=db, autocommit=True, connect_timeout=5, options='-c statement_timeout=120000 -c lock_timeout=15000')
    q(c, 'SELECT current_database(),current_user,version()')
    q(c, "SET TIME ZONE 'America/Argentina/Buenos_Aires'")
    return c

def q(c, text, params=None):
    cur = c.execute(text, params)
    results = []
    while True:
        results.append({'estado':cur.statusmessage,'filas':cur.fetchall() if cur.description else None})
        if not cur.nextset(): break
    R['eventos'].append({'sql':text,'parametros':params,'salida':results})
    return results[0]['filas']

def scalar(c,text,params=None): return q(c,text,params)[0][0]

def check(name, value):
    R['pruebas'].append({'prueba':name,'correcto':bool(value)})
    print(('OK ' if value else 'ERROR ')+name,flush=True)
    assert value,name

def expected(c,name,code,text):
    q(c,'SAVEPOINT esperado')
    try: q(c,text)
    except psycopg.Error as e:
        R['eventos'].append({'sql':text,'error':str(e),'sqlstate':e.sqlstate})
        q(c,'ROLLBACK TO SAVEPOINT esperado')
        check(name,e.sqlstate==code)
    else: raise AssertionError(name)
    finally: q(c,'RELEASE SAVEPOINT esperado')

def audit(c,name):
    check(name,scalar(c,'SELECT count(*) FROM unidad4.auditoria_ventas')==0)
    check(name+' top equivalente',q(c,'SELECT * FROM unidad4.top_categorias_normalizado')==
          q(c,'SELECT * FROM unidad4.top_categorias_materializado'))

def backup(label):
    p=REPO/'backups'/(DB+'_'+label+'.dump');p.parent.mkdir(exist_ok=True)
    subprocess.run([str(args.pg_bin/'pg_dump'),'-h',args.host,'-p',str(args.port),
                    '-U',args.user,'-Fc','-f',str(p),DB],check=True)

def script(c,path): q(c,(REPO/path).read_text(encoding='utf-8-sig'))

def mutations(c):
    q(c,'BEGIN')
    for name,statement in [
        ('INSERT detalle',"INSERT INTO detalle_pedido VALUES (1,600,10,2)"),
        ('UPDATE cantidad y precio',"UPDATE detalle_pedido SET cantidad=3,precio_unitario=12 WHERE id_pedido=1 AND id_producto=600"),
        ('UPDATE producto de detalle',"UPDATE detalle_pedido SET id_producto=599 WHERE id_pedido=1 AND id_producto=600"),
        ('UPDATE pedido de detalle',"UPDATE detalle_pedido SET id_pedido=2 WHERE id_pedido=1 AND id_producto=599"),
        ('DELETE detalle',"DELETE FROM detalle_pedido WHERE id_pedido=2 AND id_producto=599"),
        ('UPDATE fecha',"UPDATE pedido SET fecha=fecha-interval '2 days' WHERE id_pedido=1"),
        ('UPDATE categoria producto',"UPDATE producto SET categoria_id=2 WHERE id_producto=1"),
        ('UPDATE nombre categoria',"UPDATE categoria SET nombre='Renombrada U4' WHERE id_categoria=2"),
        ('Baja logica producto',"CALL tpi_baja_producto(1)"),
        ('Baja logica categoria',"UPDATE categoria SET activo=false WHERE id_categoria=2"),
    ]:
        q(c,statement);audit(c,name)
    q(c,'ROLLBACK');audit(c,'ROLLBACK integral')
    q(c,'BEGIN')
    q(c,"INSERT INTO categoria(nombre) VALUES ('Solo U4')")
    q(c,"INSERT INTO producto(nombre,precio_lista,stock,categoria_id) SELECT 'Solo U4',7,100,id_categoria FROM categoria WHERE nombre='Solo U4'")
    q(c,"INSERT INTO detalle_pedido SELECT 1,id_producto,7,1 FROM producto WHERE nombre='Solo U4'")
    audit(c,'Nueva categoria con venta')
    q(c,"DELETE FROM detalle_pedido WHERE id_producto=(SELECT id_producto FROM producto WHERE nombre='Solo U4')")
    audit(c,'Borrar ultima venta de categoria')
    q(c,'ROLLBACK')
    q(c,'BEGIN')
    before=q(c,'SELECT * FROM unidad4.top_categorias_normalizado')
    q(c,"SET TIME ZONE 'UTC'")
    check('Dia comercial independiente de zona de sesion',before==q(c,'SELECT * FROM unidad4.top_categorias_normalizado'))
    q(c,"SET TIME ZONE 'America/Argentina/Buenos_Aires'")
    expected(c,'Reglas anteriores siguen activas','23514',"UPDATE detalle_pedido SET cantidad=0 WHERE id_pedido=1")
    q(c,'ROLLBACK')
    q(c,'BEGIN ISOLATION LEVEL REPEATABLE READ')
    expected(c,'Rechazo explicito aislamiento incompatible','0A000','UPDATE producto SET stock=stock WHERE id_producto=1')
    q(c,'ROLLBACK')
    q(c,'BEGIN')
    q(c,'TRUNCATE detalle_pedido')
    audit(c,'TRUNCATE sincronizado')
    check('Materializada vacia tras TRUNCATE',scalar(c,'SELECT count(*) FROM unidad4.ventas_categoria_diaria')==0)
    q(c,'ROLLBACK');audit(c,'ROLLBACK de TRUNCATE')
    q(c,'BEGIN')
    q(c,'ALTER TABLE detalle_pedido DISABLE TRIGGER u4_ventas_sincronia')
    q(c,'UPDATE detalle_pedido SET precio_unitario=precio_unitario+1 WHERE id_pedido=1')
    check('Auditoria detecta desincronizacion inducida',scalar(c,'SELECT count(*) FROM unidad4.auditoria_ventas')>0)
    q(c,'ROLLBACK');audit(c,'Recuperacion tras corrupcion inducida')
    q(c,'BEGIN')
    q(c,'ALTER TABLE detalle_pedido DISABLE TRIGGER u4_ventas_sincronia')
    q(c,'DELETE FROM detalle_pedido')
    check('Auditoria detecta resumen sobrante sin ventas fuente',scalar(c,'SELECT count(*) FROM unidad4.auditoria_ventas')>0)
    q(c,'ROLLBACK')
    q(c,'BEGIN')
    for label,value in [('medianoche',"CURRENT_DATE::timestamptz"),
                        ('ultimo instante',"CURRENT_DATE+interval '1 day'-interval '1 microsecond'"),
                        ('dia siguiente',"CURRENT_DATE+interval '1 day'")]:
        q(c,'UPDATE pedido SET fecha='+value+' WHERE id_pedido=1')
        audit(c,'Limite de fecha '+label)
    q(c,'ROLLBACK')

def lotes(c):
    check('Migracion sin diferencias',scalar(c,'SELECT count(*) FROM unidad4.auditoria_migracion')==0)
    check('Vista reconstruye tres filas',scalar(c,'SELECT count(*) FROM unidad4.vista_control_lote_almacen')==3)
    q(c,'BEGIN')
    expected(c,'Anomalia insercion original sin lote','23502','INSERT INTO unidad4.control_lote_almacen VALUES (NULL,30,803)')
    q(c,'DELETE FROM unidad4.control_lote_almacen WHERE lote_id=503')
    check('Anomalia borrado pierde pertenencia de 802',scalar(c,'SELECT count(*) FROM unidad4.control_lote_almacen WHERE responsable_control_id=802')==0)
    q(c,'UPDATE unidad4.control_lote_almacen SET deposito_id=31 WHERE lote_id=502')
    check('Anomalia actualizacion permite dos depositos para 801',scalar(c,'SELECT count(DISTINCT deposito_id) FROM unidad4.control_lote_almacen WHERE responsable_control_id=801')==2)
    q(c,'ROLLBACK')
    q(c,'BEGIN')
    expected(c,'FK lote','23503','INSERT INTO unidad4.control_lote VALUES (999,801)')
    expected(c,'FK usuario','23503','INSERT INTO unidad4.responsable_deposito VALUES (999,30)')
    expected(c,'FK deposito','23503','INSERT INTO unidad4.responsable_deposito VALUES (803,999)')
    q(c,'INSERT INTO unidad4.responsable_deposito VALUES (803,30)')
    expected(c,'LD determina R tras descomposicion','23514','INSERT INTO unidad4.control_lote VALUES (501,803)')
    q(c,'INSERT INTO unidad4.control_lote VALUES (501,802)')
    expected(c,'Cambio de deposito conserva LD determina R','23514','UPDATE unidad4.responsable_deposito SET deposito_id=30 WHERE responsable_control_id=802')
    q(c,'ROLLBACK')

def concurrent(c):
    def worker(statement):
        with connect() as b:
            pid=scalar(b,'SELECT pg_backend_pid()')
            shared.append(pid)
            try:
                q(b,statement)
                return 'OK'
            except psycopg.Error as e:
                R['eventos'].append({'sql':statement,'sqlstate':e.sqlstate,'error':str(e)})
                return e.sqlstate
    def wait_lock(future):
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            if shared and scalar(c,"SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE pid=%s AND wait_event_type='Lock')",(shared[0],)):
                return True
            if future.done(): return False
            time.sleep(.05)
        return False
    shared=[]
    q(c,'BEGIN')
    q(c,'UPDATE detalle_pedido SET precio_unitario=precio_unitario+1 WHERE id_pedido=1')
    with ThreadPoolExecutor(max_workers=1) as pool:
        f=pool.submit(worker,'UPDATE detalle_pedido SET precio_unitario=precio_unitario+2 WHERE id_pedido=2')
        blocked=wait_lock(f)
        q(c,'COMMIT')
        result=f.result()
    check('Escrituras concurrentes serializadas',blocked and result=='OK')
    audit(c,'Sincronizacion tras dos COMMIT concurrentes')
    shared.clear()
    q(c,'BEGIN')
    q(c,'INSERT INTO unidad4.responsable_deposito VALUES (803,30)')
    q(c,'INSERT INTO unidad4.control_lote VALUES (503,801)')
    with ThreadPoolExecutor(max_workers=1) as pool:
        f=pool.submit(worker,'INSERT INTO unidad4.control_lote VALUES (503,803)')
        blocked=wait_lock(f)
        q(c,'COMMIT')
        result=f.result()
    check('Conflicto concurrente LD determina R rechazado',blocked and result=='23514')
    q(c,'DELETE FROM unidad4.control_lote WHERE lote_id=503 AND responsable_control_id=801')
    q(c,'DELETE FROM unidad4.responsable_deposito WHERE responsable_control_id=803')

def measure(c):
    for label,view in [('antes','top_categorias_normalizado'),('despues','top_categorias_materializado')]:
        statement='SELECT * FROM unidad4.'+view
        q(c,statement)
        plans=[scalar(c,'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '+statement)[0] for _ in range(5)]
        (OUT/(label+'.json')).write_text(json.dumps(plans,indent=2),encoding='utf-8')
        lines=q(c,'EXPLAIN (ANALYZE, BUFFERS) '+statement)
        (OUT/(label+'.txt')).write_text('\n'.join(x[0] for x in lines),encoding='utf-8')
        R['mediciones'][label]={'tiempos_ms':[p['Execution Time'] for p in plans],
            'mediana_ms':statistics.median(p['Execution Time'] for p in plans)}
    for label in ['sin_sincronizacion','con_sincronizacion']:
        times=[]
        for _ in range(5):
            q(c,'BEGIN')
            if label=='sin_sincronizacion':q(c,'ALTER TABLE detalle_pedido DISABLE TRIGGER u4_ventas_sincronia')
            plan=scalar(c,'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) UPDATE detalle_pedido SET precio_unitario=precio_unitario+1 WHERE id_pedido=1')[0]
            times.append(plan['Execution Time'])
            q(c,'ROLLBACK')
        R['mediciones'][label]={'tiempos_ms':times,'mediana_ms':statistics.median(times)}

try:
    with connect('postgres') as admin:
        q(admin,sql.SQL('CREATE DATABASE {}').format(sql.Identifier(DB)).as_string(admin))
    with connect() as c:
        backup('vacia')
        q(c,'BEGIN')
        script(c,'schema.sql');q(c,'ROLLBACK')
        check('DDL base reversible',scalar(c,"SELECT to_regclass('public.pedido') IS NULL"))
        q(c,'BEGIN')
        script(c,'schema.sql')
        script(c,'restricciones_Food_Store.sql')
        for f in ['funciones.sql','registrar_pedido.sql','baja_producto.sql','categorias_transicion.sql']:
            script(c,'tpi/'+f)
        q(c,"INSERT INTO categoria(nombre) SELECT 'Categoria '||lpad(i::text,2,'0') FROM generate_series(1,30) i")
        q(c,"INSERT INTO cliente(correo_electronico,nombre,apellido) VALUES ('u4@example.test','Prueba','U4')")
        q(c,"INSERT INTO producto(nombre,precio_lista,stock,categoria_id) SELECT 'Producto '||i,10+i%100,100000,1+(i-1)%30 FROM generate_series(1,600) i")
        q(c,"INSERT INTO pedido(fecha,forma_pago,cliente_id) SELECT CURRENT_DATE-((i%2)*interval '1 day')+interval '12 hours','EFECTIVO',1 FROM generate_series(1,20000) i")
        q(c,"INSERT INTO detalle_pedido SELECT i,1+((i*7+j)%600),(10+((i*7+j)%100))::numeric,1+(j%3) FROM generate_series(1,20000) i CROSS JOIN generate_series(1,6) j")
        q(c,'COMMIT');q(c,'ANALYZE')
        R['entorno']=q(c,'SELECT version(),current_setting(\'TimeZone\'),current_setting(\'transaction_isolation\')')
        R['conteos']=q(c,'SELECT (SELECT count(*) FROM categoria),(SELECT count(*) FROM producto),(SELECT count(*) FROM pedido),(SELECT count(*) FROM detalle_pedido)')
        backup('antes_unidad4')
        for ending in ['ROLLBACK','COMMIT']:
            q(c,'BEGIN')
            script(c,'tpUnidad4/tp_fnbc_control_lote.sql')
            script(c,'tpUnidad4/tp_desnormalizacion_top_categorias.sql')
            audit(c,'Instalacion '+ending)
            q(c,ending)
            if ending=='ROLLBACK':
                check('Instalacion Unidad 4 reversible',scalar(c,"SELECT to_regnamespace('unidad4') IS NULL"))
        lotes(c);mutations(c);concurrent(c)
        q(c,'ANALYZE');measure(c);audit(c,'Auditoria final')
        R['auditoria_final']=q(c,'SELECT * FROM unidad4.auditoria_ventas')
        R['top_final']=q(c,'SELECT * FROM unidad4.top_categorias_materializado')
        R['exito']=True
finally:
    (OUT/'resultado.json').write_text(json.dumps(R,ensure_ascii=False,indent=2,default=str),encoding='utf-8')
    print('Evidencia:',OUT,flush=True)
