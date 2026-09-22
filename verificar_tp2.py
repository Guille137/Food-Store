"""Pruebas reales sobre bases nuevas de PostgreSQL. No modifica bases existentes."""
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
parser = argparse.ArgumentParser()
parser.add_argument('--host', default='127.0.0.1')
parser.add_argument('--port', type=int, default=5432)
parser.add_argument('--user', default='postgres')
parser.add_argument('--pg-bin', type=Path, required=True)
args = parser.parse_args()
stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
prefix = 'food_store_tp2_' + stamp
records = []
results = {}


def record(session, statement, result):
    records.append({'sesion': session, 'sql': statement, 'resultado': result})


def connect(db, label):
    c = psycopg.connect(host=args.host, port=args.port, user=args.user,
                         dbname=db, autocommit=True, application_name='tp2_' + label,
                         connect_timeout=10, options='-c statement_timeout=15000')
    c.add_notice_handler(lambda d: record(label, 'NOTICE', d.message_primary))
    run(c, label, 'SELECT current_database(), current_user, version()')
    return c


def run(c, label, statement, expected=None):
    try:
        cur = c.execute(statement)
        value = cur.fetchall() if cur.description else cur.statusmessage
        record(label, statement, value)
        if expected:
            raise AssertionError('No se produjo el error ' + expected)
        return value
    except psycopg.Error as e:
        record(label, statement, {'sqlstate': e.sqlstate, 'mensaje': e.diag.message_primary})
        if e.sqlstate != expected:
            raise
        return e.sqlstate


def script(c, name):
    content = (ROOT / name).read_text(encoding='utf-8-sig')
    record('PREPARACION', 'Archivo: ' + name, 'Inicio')
    cur = c.execute(content)
    while True:
        record('PREPARACION', name, cur.fetchall() if cur.description else cur.statusmessage)
        if not cur.nextset():
            break


def dump(db):
    folder = ROOT / 'backups'
    folder.mkdir(exist_ok=True)
    target = folder / (db + '_pre_ddl.dump')
    command = [str(args.pg_bin / 'pg_dump'), '-h', args.host, '-p', str(args.port),
               '-U', args.user, '-Fc', '-f', str(target), db]
    subprocess.run(command, check=True, capture_output=True)
    record('PREPARACION', 'pg_dump -Fc ' + db, str(target.relative_to(ROOT)))


def create_db(admin, name, template=None):
    query = sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name))
    if template:
        query += sql.SQL(' TEMPLATE {}').format(sql.Identifier(template))
    run(admin, 'ADMIN', query.as_string(admin))


def wait_blocked(admin, pid):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        rows = admin.execute('SELECT wait_event_type, wait_event FROM pg_stat_activity WHERE pid=%s', (pid,)).fetchall()
        if rows and rows[0][0] == 'Lock':
            record('OBSERVADOR', 'pg_stat_activity WHERE pid=' + str(pid), rows)
            return
        time.sleep(0.02)
    raise AssertionError('No se observo la espera por bloqueo')


def pair(admin, suffix, template):
    db = prefix + '_' + suffix
    create_db(admin, db, template)
    return connect(db, suffix + '_A'), connect(db, suffix + '_B')


def main():
    admin = connect('postgres', 'ADMIN')
    template = prefix + '_base'
    create_db(admin, template)
    with connect(template, 'BASE') as c:
        dump(template)
        # Inspección del esquema y los datos antes de confirmarlos.
        run(c, 'BASE', 'BEGIN')
        script(c, 'schema.sql')
        script(c, 'datos_iniciales.sql')
        run(c, 'BASE', 'ROLLBACK')
        run(c, 'BASE', 'BEGIN')
        script(c, 'schema.sql')
        script(c, 'datos_iniciales.sql')
        run(c, 'BASE', 'COMMIT')

    # Copia de trabajo y respaldo previos a aplicar la migración.
    work = prefix + '_trabajo'
    create_db(admin, work, template)
    with connect(work, 'RESTRICCIONES') as c:
        dump(work)
        run(c, 'RESTRICCIONES', 'BEGIN')
        script(c, 'restricciones_Food_Store.sql')
        script(c, 'pruebas_restricciones.sql')
        run(c, 'RESTRICCIONES', 'ROLLBACK')
        run(c, 'RESTRICCIONES', 'BEGIN')
        script(c, 'restricciones_Food_Store.sql')
        run(c, 'RESTRICCIONES', 'COMMIT')
        run(c, 'RESTRICCIONES', 'BEGIN')
        script(c, 'pruebas_restricciones.sql')
        run(c, 'RESTRICCIONES', 'ROLLBACK')
        assert run(c, 'RESTRICCIONES', 'SELECT count(*) FROM detalle_pedido') == [(0,)]
    results['restricciones'] = 'Pruebas validas e invalidas confirmadas; cambios de prueba revertidos'

    for kind in ['lectura', 'fantasma']:
        for isolation in ['READ COMMITTED', 'REPEATABLE READ']:
            label = kind + ('_rc' if isolation == 'READ COMMITTED' else '_rr')
            db = prefix + '_' + label
            create_db(admin, db, work)
            with connect(db, label + '_A') as a, connect(db, label + '_B') as b:
                query = ('SELECT stock FROM producto WHERE id_producto=1' if kind == 'lectura'
                         else 'SELECT count(*) FROM pedido WHERE cliente_id=1')
                change = ('UPDATE producto SET stock=stock+1 WHERE id_producto=1' if kind == 'lectura'
                          else "INSERT INTO pedido (forma_pago,cliente_id) VALUES ('EFECTIVO',1)")
                # Inspección de la escritura en la copia antes del experimento.
                run(b, label + '_B', 'BEGIN')
                run(b, label + '_B', change)
                run(b, label + '_B', 'ROLLBACK')
                run(a, label + '_A', 'BEGIN ISOLATION LEVEL ' + isolation)
                before = run(a, label + '_A', query)[0][0]
                run(b, label + '_B', 'BEGIN')
                run(b, label + '_B', change)
                run(b, label + '_B', 'COMMIT')
                after = run(a, label + '_A', query)[0][0]
                run(a, label + '_A', 'COMMIT')
                assert after == before + (1 if isolation == 'READ COMMITTED' else 0)
                results[label] = {'primera': before, 'segunda': after, 'aislamiento': isolation}

    with ThreadPoolExecutor(max_workers=1) as pool:
        a, b = pair(admin, 'bloqueo', work)
        with a, b:
            run(a, 'bloqueo_A', 'BEGIN')
            run(a, 'bloqueo_A', 'SELECT id_producto FROM producto WHERE id_producto=1 FOR UPDATE')
            run(b, 'bloqueo_B', 'BEGIN')
            start = time.monotonic()
            future = pool.submit(run, b, 'bloqueo_B', 'SELECT id_producto FROM producto WHERE id_producto=1 FOR UPDATE')
            wait_blocked(admin, b.info.backend_pid)
            assert not future.done()
            run(a, 'bloqueo_A', 'COMMIT')
            assert future.result(timeout=10) == [(1,)]
            duration = time.monotonic() - start
            run(b, 'bloqueo_B', 'COMMIT')
            run(a, 'bloqueo_A', 'BEGIN')
            run(a, 'bloqueo_A', 'SELECT id_producto FROM producto WHERE id_producto=1 FOR UPDATE')
            run(b, 'bloqueo_B', 'BEGIN')
            run(b, 'bloqueo_B', 'SELECT id_producto FROM producto WHERE id_producto=1 FOR UPDATE NOWAIT', '55P03')
            run(b, 'bloqueo_B', 'ROLLBACK')
            run(a, 'bloqueo_A', 'ROLLBACK')
            results['bloqueo'] = {'espera_observada': True, 'segundos': round(duration, 4), 'nowait_sqlstate': '55P03'}

        # Regresión: mientras se edita una línea, confirmar el pedido debe esperar.
        a, b = pair(admin, 'detalle_primero', work)
        with a, b:
            run(a, 'detalle_A', 'BEGIN')
            run(a, 'detalle_A', 'INSERT INTO detalle_pedido VALUES (1,1,1000,1)')
            run(b, 'detalle_B', 'BEGIN')
            future = pool.submit(run, b, 'detalle_B', "UPDATE pedido SET estado='CONFIRMADO' WHERE id_pedido=1")
            wait_blocked(admin, b.info.backend_pid)
            assert not future.done()
            run(a, 'detalle_A', 'ROLLBACK')
            assert future.result(timeout=10) == 'UPDATE 1'
            run(b, 'detalle_B', 'ROLLBACK')
            results['detalle_primero'] = 'El cambio de estado espera al cierre de la edicion'

        # Regresión inversa: después de confirmar, una inserción que esperaba se rechaza.
        a, b = pair(admin, 'estado_primero', work)
        with a, b:
            run(a, 'estado_A', 'BEGIN')
            run(a, 'estado_A', "UPDATE pedido SET estado='CONFIRMADO' WHERE id_pedido=1")
            run(a, 'estado_A', 'ROLLBACK')
            run(a, 'estado_A', 'BEGIN')
            run(a, 'estado_A', "UPDATE pedido SET estado='CONFIRMADO' WHERE id_pedido=1")
            run(b, 'estado_B', 'BEGIN')
            future = pool.submit(run, b, 'estado_B', 'INSERT INTO detalle_pedido VALUES (1,1,1000,1)', '23514')
            wait_blocked(admin, b.info.backend_pid)
            run(a, 'estado_A', 'COMMIT')
            assert future.result(timeout=10) == '23514'
            run(b, 'estado_B', 'ROLLBACK')
            results['estado_primero'] = 'La insercion espera y luego rechaza el pedido confirmado'

    with connect(work, 'LECTURA_CRITICA') as c:
        run(c, 'LECTURA_CRITICA', 'BEGIN')
        script(c, 'pruebas_lectura_critica.sql')
        run(c, 'LECTURA_CRITICA', 'ROLLBACK')
        results['lectura_critica'] = 'Scripts originales y corregidos comprobados con tablas temporales'
    admin.close()


if __name__ == '__main__':
    ok = False
    try:
        main()
        ok = True
    finally:
        folder = ROOT / 'evidencias'
        folder.mkdir(exist_ok=True)
        output = {'fecha_utc': stamp, 'exito': ok, 'resultados': results, 'registro': records}
        target = folder / ('ejecucion_' + stamp + '.json')
        target.write_text(json.dumps(output, ensure_ascii=False, indent=2, default=str), encoding='utf-8')
        print(target)
    print('OK: restricciones, concurrencia y lectura critica verificadas en PostgreSQL')
