"""TP4 sobre una copia nueva del TP3: planes antes, candidatos y equivalencia."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import statistics
import subprocess
import psycopg
from psycopg import sql

ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('fase',choices=['antes','despues','equivalencia'])
parser.add_argument('--sesion',type=Path,required=True)
parser.add_argument('--pg-bin',type=Path,required=True)
parser.add_argument('--host',default='127.0.0.1')
parser.add_argument('--port',type=int,default=55432)
parser.add_argument('--user',default='postgres')
args=parser.parse_args()


def connect(name):
    c=psycopg.connect(host=args.host,port=args.port,user=args.user,dbname=name,
        autocommit=True,options='-c statement_timeout=300000')
    print(c.execute('SELECT current_database(),current_user,version()').fetchone(),flush=True)
    c.execute("SET TIME ZONE 'UTC'")
    return c


def query(name):
    return (ROOT/name).read_text(encoding='utf-8').strip().rstrip(';')


def execute_script(c,name):
    cur=c.execute(query(name))
    output=[]
    while True:
        output.append(cur.fetchall() if cur.description else cur.statusmessage)
        if not cur.nextset():break
    print(name,output[-8:],flush=True)
    return output


def backup(db,label):
    target=ROOT.parent/'backups'/(db+'_'+label+'.dump')
    subprocess.run([str(args.pg_bin/'pg_dump'),'-h',args.host,'-p',str(args.port),
        '-U',args.user,'-Fc','-f',str(target),db],check=True)
    return str(target.relative_to(ROOT.parent))


def measure(c,folder,name,statement):
    c.execute('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+statement).fetchall()
    plans=[c.execute('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+statement).fetchone()[0][0] for _ in range(5)]
    text='\n'.join(row[0] for row in c.execute('EXPLAIN (ANALYZE,BUFFERS) '+statement))
    (folder/(name+'.txt')).write_text(text+'\n',encoding='utf-8')
    result={'consulta':statement,'mediana_ms':statistics.median(p['Execution Time'] for p in plans),'planes':plans}
    (folder/(name+'.json')).write_text(json.dumps(result,indent=2,default=str),encoding='utf-8')
    print(name,result['mediana_ms'],flush=True)
    return result


def compare(c,a,b):
    difference=c.execute(f'WITH a AS ({a}),b AS ({b}) SELECT (SELECT count(*) FROM (TABLE a EXCEPT ALL TABLE b) d), (SELECT count(*) FROM (TABLE b EXCEPT ALL TABLE a) d)').fetchone()
    assert difference==(0,0),difference
    rows_a=c.execute(a).fetchall()
    rows_b=c.execute(b).fetchall()
    assert rows_a==rows_b,'Orden o valores diferentes'
    return {'diferencias':difference,'filas':len(rows_a),'orden_igual':True,'muestra':rows_a[:5]}


def prepare():
    source=json.loads(args.sesion.read_text(encoding='utf-8'))['base']
    if not re.fullmatch(r'food_store_tp3_\d{8}_\d{6}',source):raise ValueError('Usar la sesion del TP3')
    stamp=datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
    db='food_store_tp4_'+stamp
    folder=ROOT/'evidencias'/stamp
    folder.mkdir(parents=True)
    with connect('postgres') as admin:
        admin.execute(sql.SQL('CREATE DATABASE {} TEMPLATE {}').format(sql.Identifier(db),sql.Identifier(source+'_trabajo')))
    s={'base':db,'fuente':source+'_trabajo','estado':'antes','mediciones':{}}
    with connect(db) as c:
        s['version']=c.execute('SELECT version()').fetchone()[0]
        s['respaldo']=backup(db,'inicial')
        s['indices_iniciales']=c.execute('SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname=\'public\' ORDER BY tablename,indexname').fetchall()
        s['conteos']=c.execute('SELECT (SELECT count(*) FROM producto),(SELECT count(*) FROM cliente),(SELECT count(*) FROM pedido),(SELECT count(*) FROM detalle_pedido)').fetchone()
        assert s['conteos']==(50003,20001,200003,600000)
        c.execute('VACUUM (ANALYZE)')
        s['configuracion']=c.execute("SELECT name,setting FROM pg_settings WHERE name IN ('work_mem','shared_buffers','random_page_cost','seq_page_cost','max_parallel_workers_per_gather','jit')").fetchall()
        for i in [1,2]:s['mediciones'][f'a{i}_antes']=measure(c,folder,f'a{i}_antes',query(f'a{i}_antes.sql'))
    path=folder/'sesion.json'
    path.write_text(json.dumps(s,indent=2,default=str),encoding='utf-8')
    print('SESION',path,flush=True)


def after():
    path=args.sesion
    s=json.loads(path.read_text(encoding='utf-8'))
    assert s['estado']=='antes','Usar una sesion no optimizada'
    with connect(s['base']) as c:
        s['respaldo_indices']=backup(s['base'],'pre_indices')
        s['equivalencia_optimizacion']={}
        for i in [1,2]:
            s['equivalencia_optimizacion'][f'a{i}']=compare(c,query(f'a{i}_antes.sql'),query(f'a{i}_despues.sql'))
        s['ddl']=[]
        for end in ['ROLLBACK','COMMIT']:
            c.execute('BEGIN')
            s['ddl'].append({'cierre':end,'resultado':execute_script(c,'indices.sql')})
            c.execute(end)
        for i in [1,2]:
            # Separar aporte de índices y reescritura con datos y estadísticas constantes.
            for stage in ['solo_indices','despues']:
                statement=query(f'a{i}_antes.sql' if stage=='solo_indices' else f'a{i}_despues.sql')
                name=f'a{i}_{stage}'
                s['mediciones'][name]=measure(c,path.parent,name,statement)
        s['tamano_indices']=c.execute("SELECT indexrelname,pg_relation_size(indexrelid) FROM pg_stat_user_indexes WHERE indexrelname LIKE 'tp4_%' ORDER BY indexrelname").fetchall()
        confirmation={'metodo':'Cinco pares alternando el orden de las dos variantes, indices instalados, mismos datos',
                      'planes':{'original_indices':[],'preagregada_indices':[]}}
        for i in range(5):
            variants=[('original_indices','a2_antes.sql'),('preagregada_indices','a2_despues.sql')]
            if i%2:variants.reverse()
            for label,file in variants:
                plan=c.execute('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+query(file)).fetchone()[0][0]
                confirmation['planes'][label].append(plan)
        confirmation['medianas']={k:statistics.median(p['Execution Time'] for p in v) for k,v in confirmation['planes'].items()}
        (path.parent/'confirmacion_a2.json').write_text(json.dumps(confirmation,indent=2),encoding='utf-8')
    s['estado']='medido'
    path.write_text(json.dumps(s,indent=2,default=str),encoding='utf-8')


def equivalence():
    path=args.sesion
    s=json.loads(path.read_text(encoding='utf-8'))
    with connect(s['base']) as c:
        s['equivalencia']={}
        for kind in ['ranking','correlacionada']:
            s['equivalencia'][kind+'_masiva']=compare(c,query(kind+'_a.sql'),query(kind+'_b.sql'))
        s['respaldo_bordes']=backup(s['base'],'pre_bordes')
        c.execute('BEGIN')
        s['casos_limite']=execute_script(c,'casos_limite.sql')
        for kind in ['ranking','correlacionada']:
            s['equivalencia'][kind+'_bordes']=compare(c,query(kind+'_a.sql'),query(kind+'_b.sql'))
        s['resultados_bordes']=execute_script(c,'verificar_bordes.sql')
        c.execute('ROLLBACK')
        s['bordes_revertidos']=c.execute("SELECT count(*) FROM cliente WHERE correo_electronico LIKE 'tp4_borde_%@example.test'").fetchone()[0]
        assert s['bordes_revertidos']==0
    path.write_text(json.dumps(s,indent=2,default=str),encoding='utf-8')


if __name__=='__main__':
    {'antes':prepare,'despues':after,'equivalencia':equivalence}[args.fase]()
