"""TP3: preparación y mediciones reales, separadas para analizar el plan antes del cambio."""
import argparse
from datetime import datetime, timezone
import json
import re
from pathlib import Path
import statistics
import subprocess
import time

import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
parser = argparse.ArgumentParser()
parser.add_argument('fase', choices=['antes', 'despues', 'equivalencia'])
parser.add_argument('--pg-bin', type=Path, required=True)
parser.add_argument('--host', default='127.0.0.1')
parser.add_argument('--port', type=int, default=55432)
parser.add_argument('--user', default='postgres')
parser.add_argument('--sesion', type=Path)
args = parser.parse_args()


def connection(name):
    c = psycopg.connect(host=args.host, port=args.port, user=args.user, dbname=name,
                         autocommit=True, options='-c statement_timeout=600000')
    print(c.execute('SELECT current_database(),current_user,version()').fetchone(), flush=True)
    c.execute("SET TIME ZONE 'UTC'")
    return c


def execute_file(c, path):
    print('Ejecutando', path.name, flush=True)
    t = time.monotonic()
    cur = c.execute(path.read_text(encoding='utf-8-sig'))
    output = []
    while True:
        output.append(cur.fetchall() if cur.description else cur.statusmessage)
        if not cur.nextset():
            break
    print('Resultado', output[-5:], 'segundos', round(time.monotonic()-t, 2), flush=True)
    return output


def backup(name, suffix):
    target = REPO/'backups'/(name+'_'+suffix+'.dump')
    target.parent.mkdir(exist_ok=True)
    subprocess.run([str(args.pg_bin/'pg_dump'), '-h', args.host, '-p', str(args.port),
                    '-U', args.user, '-Fc', '-f', str(target), name], check=True)
    return str(target.relative_to(REPO))


def create(admin, name, template=None):
    q = sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name))
    if template:
        q += sql.SQL(' TEMPLATE {}').format(sql.Identifier(template))
    admin.execute(q)


def queries(path):
    # Estos archivos contienen SELECT simples. Excluir comentarios antes de separar.
    content = re.sub(r'--[^\n]*', '', path.read_text(encoding='utf-8'))
    return [s.strip() for s in content.split(';') if s.strip()]


def measure(c, folder, phase, statements):
    output = []
    for i, statement in enumerate(statements, 1):
        # Un calentamiento idéntico y cinco medidas; se conserva cada plan completo.
        c.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '+statement).fetchall()
        plans = [c.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '+statement).fetchone()[0][0]
                 for _ in range(5)]
        text = '\n'.join(r[0] for r in c.execute('EXPLAIN (ANALYZE, BUFFERS) '+statement))
        (folder/f'q{i}_{phase}.txt').write_text(text+'\n', encoding='utf-8')
        item = {'consulta': statement, 'planes': plans,
                'mediana_ms': statistics.median(p['Execution Time'] for p in plans)}
        (folder/f'q{i}_{phase}.json').write_text(json.dumps(item, indent=2, default=str), encoding='utf-8')
        print('Q', i, phase, 'mediana ms', item['mediana_ms'], flush=True)
        output.append(item)
    return output


def prepare():
    if args.sesion:
        session=json.loads(args.sesion.read_text(encoding='utf-8'))
        base=session['base']
        if not re.fullmatch(r'food_store_tp3_\d{8}_\d{6}',base) or session['estado']!='preparando':
            raise ValueError('Solo se reanuda una preparación propia interrumpida')
        with connection(base+'_ensayo') as c:
            assert c.execute('SELECT count(*) FROM detalle_pedido').fetchone()[0]==0
        with connection(base+'_trabajo') as c:
            session['conteos']=dict(c.execute("SELECT 'producto',count(*) FROM producto UNION ALL SELECT 'cliente',count(*) FROM cliente UNION ALL SELECT 'pedido',count(*) FROM pedido UNION ALL SELECT 'detalle_pedido',count(*) FROM detalle_pedido"))
            assert session['conteos']=={'producto':50003,'cliente':20001,'pedido':200003,'detalle_pedido':600000}
            session['configuracion']=dict(c.execute("SELECT name,setting FROM pg_settings WHERE name IN ('shared_buffers','work_mem','random_page_cost','seq_page_cost','max_parallel_workers_per_gather','jit')"))
            c.execute('VACUUM (ANALYZE)')
            session['antes']=measure(c,args.sesion.parent,'antes',queries(ROOT/'consultas_lentas.sql'))
        session['estado']='planes_antes_disponibles'
        session['reanudada']=True
        args.sesion.write_text(json.dumps(session,indent=2,default=str),encoding='utf-8')
        return
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
    base = 'food_store_tp3_'+stamp
    folder = ROOT/'evidencias'/stamp
    folder.mkdir(parents=True)
    session = {'base': base, 'carpeta': str(folder), 'fecha_utc': stamp, 'estado': 'preparando'}
    path = folder/'sesion.json'
    path.write_text(json.dumps(session, indent=2), encoding='utf-8')
    with connection('postgres') as admin:
        create(admin, base+'_plantilla')
        with connection(base+'_plantilla') as c:
            session['backup_plantilla'] = backup(base+'_plantilla','pre_ddl')
            for end in ['ROLLBACK', 'COMMIT']:
                c.execute('BEGIN')
                for name in ['schema.sql','datos_iniciales.sql','restricciones_Food_Store.sql']:
                    execute_file(c, REPO/name)
                c.execute(end)
        for suffix, end in [('ensayo','ROLLBACK'), ('trabajo','COMMIT')]:
            name = base+'_'+suffix
            create(admin, name, base+'_plantilla')
            with connection(name) as c:
                session['backup_'+suffix] = backup(name,'pre_carga')
                c.execute('BEGIN')
                result = execute_file(c, ROOT/'carga_masiva.sql')
                counts = dict(result[-1])
                assert counts == {'productos_generados':50000,'clientes_generados':20000,'pedidos_generados':200000}, counts
                actual = c.execute('SELECT (SELECT count(*) FROM producto),(SELECT count(*) FROM cliente),'
                                   '(SELECT count(*) FROM pedido),(SELECT count(*) FROM detalle_pedido)').fetchone()
                assert actual == (50003,20001,200003,600000), actual
                c.execute(end)
                session[suffix] = {'resultado': result, 'conteos': actual, 'cierre':end}
                if suffix=='ensayo':
                    assert c.execute('SELECT count(*) FROM detalle_pedido').fetchone()[0]==0
        with connection(base+'_trabajo') as c:
            # Mismo mantenimiento previo a ambas fases; no se fuerzan planes.
            c.execute('VACUUM (ANALYZE)')
            session['configuracion'] = dict(c.execute("SELECT name,setting FROM pg_settings WHERE name IN ('shared_buffers','work_mem','random_page_cost','seq_page_cost','max_parallel_workers_per_gather','jit')"))
            session['conteos'] = dict(c.execute("SELECT 'producto',count(*) FROM producto UNION ALL SELECT 'cliente',count(*) FROM cliente UNION ALL SELECT 'pedido',count(*) FROM pedido UNION ALL SELECT 'detalle_pedido',count(*) FROM detalle_pedido"))
            path.write_text(json.dumps(session, indent=2, default=str), encoding='utf-8')
            session['antes'] = measure(c, folder, 'antes', queries(ROOT/'consultas_lentas.sql'))
            session['estado'] = 'planes_antes_disponibles'
    path.write_text(json.dumps(session, indent=2, default=str), encoding='utf-8')
    print('SESION', path, flush=True)


def after():
    if not args.sesion:
        raise ValueError('Indicar --sesion con el JSON de la fase antes')
    s = json.loads(args.sesion.read_text(encoding='utf-8'))
    if s['estado'] != 'planes_antes_disponibles':
        raise ValueError('La fase despues necesita una sesion nueva medida antes')
    folder = args.sesion.parent
    with connection(s['base']+'_trabajo') as c:
        s['backup_indices'] = backup(s['base']+'_trabajo','pre_indices')
        # Revisar la semántica antes de instalar los índices.
        old, new = queries(ROOT/'consultas_lentas.sql'), queries(ROOT/'consultas_optimizadas.sql')
        s['equivalencia_optimizacion'] = []
        for a,b in zip(old,new,strict=True):
            # CTEs aíslan los comentarios y preservan LIMIT/ORDER de cada consulta.
            q = f'WITH a AS ({a}), b AS ({b}) SELECT (SELECT count(*) FROM ((TABLE a) EXCEPT ALL (TABLE b)) d), (SELECT count(*) FROM ((TABLE b) EXCEPT ALL (TABLE a)) d)'
            diff=c.execute(q).fetchone()
            assert diff==(0,0), diff
            assert c.execute(a).fetchall()==c.execute(b).fetchall()
            s['equivalencia_optimizacion'].append(diff)
        c.execute('BEGIN')
        execute_file(c, ROOT/'indices.sql')
        c.execute('ROLLBACK')
        c.execute('BEGIN')
        execute_file(c, ROOT/'indices.sql')
        c.execute('COMMIT')
        c.execute('VACUUM (ANALYZE)')
        s['despues']=measure(c,folder,'despues',new)
        s['estado']='optimizaciones_medidas'
    args.sesion.write_text(json.dumps(s,indent=2,default=str),encoding='utf-8')


def equivalence():
    if not args.sesion:
        raise ValueError('Indicar --sesion')
    s=json.loads(args.sesion.read_text(encoding='utf-8'))
    with connection(s['base']+'_trabajo') as c:
        c.execute('BEGIN')
        s['equivalencia_parte4']=execute_file(c,ROOT/'verificar_equivalencia.sql')
        s['orden_parte4']={}
        for kind in ['resumen','subconsulta']:
            a=c.execute((ROOT/f'parte4_{kind}_a.sql').read_text(encoding='utf-8')).fetchall()
            b=c.execute((ROOT/f'parte4_{kind}_b.sql').read_text(encoding='utf-8')).fetchall()
            assert a==b
            s['orden_parte4'][kind]={'filas':len(a),'muestra':a[:5],'mismo_orden':True}
        c.execute('ROLLBACK')
    args.sesion.write_text(json.dumps(s,indent=2,default=str),encoding='utf-8')


if __name__=='__main__':
    {'antes':prepare,'despues':after,'equivalencia':equivalence}[args.fase]()
