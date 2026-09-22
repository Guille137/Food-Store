"""Compara el ejemplo de la Parte 5 en una copia nueva; conserva planes reales."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import statistics
import subprocess

import psycopg
from psycopg import sql

root=Path(__file__).resolve().parent
p=argparse.ArgumentParser()
p.add_argument('--sesion',type=Path,required=True)
p.add_argument('--pg-bin',type=Path,required=True)
p.add_argument('--host',default='127.0.0.1')
p.add_argument('--port',type=int,default=55432)
p.add_argument('--user',default='postgres')
args=p.parse_args()
source=json.loads(args.sesion.read_text(encoding='utf-8'))['base']
if not re.fullmatch(r'food_store_tp3_\d{8}_\d{6}',source):
    raise ValueError('La fuente debe ser una copia del laboratorio TP3')
stamp=datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
db='food_store_tp3_competencia_'+stamp
folder=root/'evidencias'/('competencia_'+stamp)
folder.mkdir(parents=True)
record={'base':db,'fuente':source+'_trabajo','resultados':{},'ddl':[],'exito':False}


def connect(name):
    c=psycopg.connect(host=args.host,port=args.port,user=args.user,dbname=name,
                      autocommit=True,options='-c statement_timeout=60000')
    identity=c.execute('SELECT current_database(),current_user,version()').fetchone()
    print(identity,flush=True)
    record.setdefault('conexiones',[]).append(identity)
    return c


def change(c,commands,label):
    target=root.parent/'backups'/(db+'_'+label+'.dump')
    subprocess.run([str(args.pg_bin/'pg_dump'),'-h',args.host,'-p',str(args.port),
                    '-U',args.user,'-Fc','-f',str(target),db],check=True)
    for end in ['ROLLBACK','COMMIT']:
        c.execute('BEGIN')
        for command in commands:
            result=c.execute(command).statusmessage
            record['ddl'].append({'sql':command,'resultado':result,'cierre':end})
        c.execute(end)


def measure(c,label,query):
    c.execute('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+query).fetchall()
    plans=[c.execute('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+query).fetchone()[0][0] for _ in range(5)]
    text='\n'.join(r[0] for r in c.execute('EXPLAIN (ANALYZE,BUFFERS) '+query))
    (folder/(label+'.txt')).write_text(text+'\n',encoding='utf-8')
    record['resultados'][label]={'planes':plans,'mediana_ms':statistics.median(x['Execution Time'] for x in plans)}
    print(label,record['resultados'][label]['mediana_ms'],flush=True)
    return c.execute(query).fetchall()


try:
    with connect('postgres') as admin:
        admin.execute(sql.SQL('CREATE DATABASE {} TEMPLATE {}').format(sql.Identifier(db),sql.Identifier(source+'_trabajo')))
    with connect(db) as c:
        query=(root/'competencia.sql').read_text(encoding='utf-8')
        record['consulta']=query
        record['indices_originales']=c.execute("SELECT indexname,indexdef FROM pg_indexes WHERE tablename='producto' ORDER BY indexname").fetchall()
        # Solo en la copia recién creada: retirar los índices aplicables al ejemplo.
        change(c,['DROP INDEX tp3_producto_categoria_precio','DROP INDEX idx_producto_categoria'],'preparacion')
        c.execute('VACUUM (ANALYZE) producto')
        baseline=measure(c,'sin_indice',query)
        candidates={
            'categoria_simple':'CREATE INDEX tp3_comp_simple ON producto(categoria_id)',
            'compuesto_parcial':'CREATE INDEX tp3_comp_compuesto ON producto(categoria_id,precio_lista,id_producto) INCLUDE(nombre) WHERE activo=TRUE'
        }
        current=None
        for label,ddl in candidates.items():
            commands=([f'DROP INDEX {current}'] if current else [])+[ddl]
            change(c,commands,label)
            current='tp3_comp_simple' if label=='categoria_simple' else 'tp3_comp_compuesto'
            actual=measure(c,label,query)
            assert actual==baseline, 'La optimizacion cambia los resultados o su orden'
            record['resultados'][label]['equivalencia_ordenada']=True
        winner=min(record['resultados'],key=lambda x:record['resultados'][x]['mediana_ms'])
        record['estrategia_elegida']=winner
        if winner!='compuesto_parcial':
            commands=[f'DROP INDEX {current}']
            if winner=='categoria_simple':commands.append(candidates[winner])
            change(c,commands,'eleccion_final')
        record['filas']=len(baseline)
        record['muestra']=baseline[:5]
        record['configuracion']=c.execute("SELECT name,setting FROM pg_settings WHERE name IN ('shared_buffers','work_mem','random_page_cost','seq_page_cost','max_parallel_workers_per_gather','jit')").fetchall()
        record['exito']=True
finally:
    (folder/'resultados.json').write_text(json.dumps(record,indent=2,ensure_ascii=False,default=str),encoding='utf-8')
    print(folder,flush=True)
