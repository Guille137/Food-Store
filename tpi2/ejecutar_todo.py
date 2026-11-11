"""Segunda entrega del TPI Food Store: instala, prueba y deja evidencia de las unidades 4 a 8.

Crea una base NUEVA con nombre fechado (nunca pisa una existente), ejecuta los
scripts de cada unidad en orden y guarda las salidas reales en
tpi2/evidencias/<fecha_hora>/. Termina con código distinto de cero si alguna
comprobación no da el resultado previsto.

Uso (PowerShell, desde la raíz del repositorio):
    $env:PGPASSFILE = "C:\\ruta\\pgpass.conf"      # clave del superusuario de laboratorio
    python tpi2/ejecutar_todo.py --pg-bin "C:\\Program Files\\PostgreSQL\\17\\bin" --port 5432 `
        --mongosh mongosh --mongo-uri mongodb://127.0.0.1:27017

Requisitos: PostgreSQL 16+ (probado en 17), MongoDB + mongosh, Python 3.10+.
No requiere paquetes de Python adicionales.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent / 'u5'))
sys.path.insert(0, str(Path(__file__).resolve().parent / 'u8'))

from lab import Lab, FalloEsperado, REPO, ROLES_LOGIN, TPI2, argumentos, sello  # noqa: E402


def transaccion(lab: Lab, *archivos: str, final: str = 'COMMIT', **kw) -> str:
    """Ejecuta los archivos en una única transacción que termina en COMMIT o ROLLBACK."""
    args = ['-c', 'BEGIN']
    for a in archivos:
        args += ['-f', a]
    args += ['-c', final]
    return lab.psql(*args, **kw).stdout


def variables_claves(lab: Lab) -> dict:
    return {variable: lab.claves[rol] for rol, variable in ROLES_LOGIN.items()}


# --------------------------------------------------------------------------- base
def paso_base(lab: Lab) -> None:
    lab.titulo('Base común: esquema de las unidades 1-3 y datos sintéticos')
    lab.herramienta('createdb', lab.base)
    salida = lab.psql('-f', 'tpi2/base/01_instalar_base.sql').stdout
    lab.guardar('base_instalacion.txt', salida[-2500:])
    conteos = lab.valor("SELECT (SELECT count(*) FROM pedido) || ' pedidos, ' || "
                        "(SELECT count(*) FROM detalle_pedido) || ' líneas, ' || "
                        "(SELECT count(*) FROM cliente) || ' clientes, ' || "
                        "(SELECT count(*) FROM producto) || ' productos'")
    lab.comprobar('Base instalada en una transacción', 'pedidos' in conteos, conteos)
    motor = lab.valor('SHOW server_version')
    lab.comprobar('Motor PostgreSQL 16 o superior', int(motor.split('.')[0]) >= 16, motor)


# ----------------------------------------------------------------------------- U4
def paso_u4(lab: Lab) -> None:
    lab.titulo('Unidad 4: esquema heredado, dependencias, migración reversible')
    transaccion(lab, 'tpi2/u4/01_esquema_heredado.sql')
    dependencias = lab.psql('-f', 'tpi2/u4/02_verificar_dependencias.sql').stdout
    lab.guardar('u4_01_dependencias_funcionales.txt', dependencias)
    lab.comprobar('DF validadas contra los datos del legado', 'viola_canonico' in dependencias)

    # Respaldo previo a la migración (nivel 3 del plan de reversión).
    respaldo = lab.carpeta / 'respaldos' / 'pre_migracion.dump'
    respaldo.parent.mkdir(parents=True, exist_ok=True)
    lab.herramienta('pg_dump', '-Fc', '-f', str(respaldo), lab.base)
    lab.comprobar('Respaldo previo a la migración', respaldo.stat().st_size > 0,
                  f'{respaldo.stat().st_size} bytes')

    antes = lab.huella()
    bitacora = ['HUELLA DE CONTENIDO (tabla|filas|md5) EN CADA ETAPA', '', '--- antes de migrar', antes]

    # 1) Ensayo: la misma migración y la misma verificación, terminando en ROLLBACK.
    ensayo = transaccion(lab, 'tpi2/u4/03_migracion.sql', 'tpi2/u4/04_verificar_migracion.sql', final='ROLLBACK')
    lab.guardar('u4_02_ensayo_con_rollback.txt', ensayo)
    lab.comprobar('Ensayo de migración verificado', 'MIGRACION VERIFICADA' in ensayo)
    tras_ensayo = lab.huella()
    bitacora += ['', '--- después del ensayo con ROLLBACK', tras_ensayo]
    lab.comprobar('ROLLBACK deja la base idéntica', tras_ensayo == antes)

    # 2) Migración confirmada.
    definitiva = transaccion(lab, 'tpi2/u4/03_migracion.sql', 'tpi2/u4/04_verificar_migracion.sql')
    lab.comprobar('Migración confirmada y verificada', 'MIGRACION VERIFICADA' in definitiva)
    tras_commit = lab.huella()
    bitacora += ['', '--- después de migrar con COMMIT', tras_commit]
    lab.comprobar('La migración cambió el contenido', tras_commit != antes)

    # 3) Reversión de una migración ya confirmada.
    reversion = transaccion(lab, 'tpi2/u4/05_reversion.sql')
    lab.guardar('u4_03_reversion.txt', reversion)
    tras_reversion = lab.huella()
    bitacora += ['', '--- después de ejecutar 05_reversion.sql', tras_reversion]
    lab.comprobar('La reversión deja la base idéntica al estado previo', tras_reversion == antes)

    # 4) Un error a mitad de la migración no deja nada a medias.
    fallo = lab.psql('-v', 'ON_ERROR_STOP=1', '-c', 'BEGIN', '-f', 'tpi2/u4/03_migracion.sql',
                     '-c', 'SELECT 1 / 0 AS error_provocado', '-c', 'COMMIT', tolerar_error=True).stdout
    lab.comprobar('Error provocado corta la migración', 'division by zero' in fallo)
    lab.comprobar('Tras el error no quedó nada aplicado', lab.huella() == antes)

    # 5) Aplicación definitiva.
    final = transaccion(lab, 'tpi2/u4/03_migracion.sql', 'tpi2/u4/04_verificar_migracion.sql')
    lab.guardar('u4_04_migracion_definitiva.txt', final)
    lab.comprobar('Migración definitiva verificada', 'MIGRACION VERIFICADA' in final)
    lab.guardar('u4_05_huellas.txt', '\n'.join(bitacora) + '\n')

    resumen = lab.sql("""
        \\echo 'Claves que ahora hacen cumplir las dependencias funcionales'
        SELECT conrelid::regclass AS tabla, conname AS restriccion, pg_get_constraintdef(oid) AS definicion
        FROM pg_constraint
        WHERE conrelid IN ('public.zona'::regclass, 'public.repartidor'::regclass, 'public.entrega'::regclass)
        ORDER BY 1, contype DESC, 2;
        \\echo 'Renglones en cuarentena (no migrables, conservados con su motivo)'
        SELECT nro_planilla, renglon, cliente_email, producto, motivo FROM migracion.cuarentena ORDER BY 1, 2;
        \\echo 'Valores del legado no trasladados'
        SELECT * FROM migracion.discrepancia ORDER BY 1, 2, 3, 4;
        \\echo 'Desnormalización controlada: fuente normalizada vs materializada (0 filas = sincronizadas)'
        SELECT count(*) AS diferencias FROM unidad4.auditoria_ventas;
    """)
    lab.guardar('u4_06_resultado_modelo.txt', resumen)


# ----------------------------------------------------------------------------- U5
def pruebas_por_rol(lab: Lab) -> str:
    """Pruebas positivas y negativas: cada rol hace lo suyo y nada más."""
    casos = [
        ('app_web', 'ver el catálogo vigente', 'SELECT count(*) FROM tp5_productos_vigentes', True),
        ('app_web', 'registrar un pedido por el procedimiento',
         "BEGIN; CALL tpi_registrar_pedido(5, 'EFECTIVO', '[{\"id_producto\": 1, \"cantidad\": 2}]'::jsonb, NULL); ROLLBACK", True),
        ('app_web', 'insertar un pedido a mano', "INSERT INTO pedido (forma_pago, cliente_id) VALUES ('EFECTIVO', 1)", False),
        ('app_web', 'leer la tabla usuario', 'SELECT count(*) FROM usuario', False),
        ('app_web', 'borrar un cliente', 'DELETE FROM cliente WHERE id_cliente = 1', False),
        ('app_web', 'leer la auditoría', 'SELECT count(*) FROM auditoria.registro', False),
        ('soporte_01', 'ver usuarios sin el hash', 'SELECT id_usuario, correo_electronico, activo FROM usuario LIMIT 1', True),
        ('soporte_01', 'leer el hash de las contraseñas', 'SELECT password_hash FROM usuario LIMIT 1', False),
        ('soporte_01', 'corregir el teléfono de un cliente',
         "BEGIN; UPDATE cliente SET nro_telefono = '+54 9 11 5555-0002' WHERE id_cliente = 2; ROLLBACK", True),
        ('soporte_01', 'cambiar el nombre de un cliente', "UPDATE cliente SET nombre = 'X' WHERE id_cliente = 2", False),
        ('soporte_01', 'cambiar un precio', 'UPDATE producto SET precio_lista = 1 WHERE id_producto = 1', False),
        ('analista_01', 'leer clientes anonimizados', 'SELECT count(*) FROM anon.cliente_anon', True),
        ('analista_01', 'leer la facturación mensual', 'SELECT count(*) FROM tp5_facturacion_mensual', True),
        ('analista_01', 'leer la tabla cliente real', 'SELECT count(*) FROM cliente', False),
        ('analista_01', 'leer la sal de los seudónimos', 'SELECT * FROM seguridad.sal', False),
        ('auditor_01', 'leer la auditoría', 'SELECT count(*) FROM auditoria.registro', True),
        ('auditor_01', 'borrar la auditoría', 'DELETE FROM auditoria.registro', False),
        ('auditor_01', 'leer pedidos', 'SELECT count(*) FROM public.pedido', False),
        ('admin_datos', 'cambiar un precio', 'BEGIN; UPDATE producto SET precio_lista = precio_lista + 1 WHERE id_producto = 1; ROLLBACK', True),
        ('admin_datos', 'dar de baja lógica un producto', 'BEGIN; CALL tpi_baja_producto(2); ROLLBACK', True),
        ('admin_datos', 'borrar físicamente un producto', 'DELETE FROM producto WHERE id_producto = 80', False),
        ('admin_datos', 'leer el hash de las contraseñas', 'SELECT password_hash FROM usuario LIMIT 1', False),
        ('admin_datos', 'crear una tabla', 'CREATE TABLE public.x (a integer)', False),
        ('operador_respaldo', 'leer para respaldar', 'SELECT count(*) FROM pedido', True),
        ('operador_respaldo', 'modificar datos', 'UPDATE producto SET stock = 0', False),
        ('tablet_feria', 'leer clientes', 'SELECT count(*) FROM public.cliente', False),
    ]
    lineas = [f"{'rol':<18} {'resultado':<10} {'previsto':<10} operación"]
    for rol, descripcion, sql, permitido in casos:
        r = lab.psql('-At', '-c', sql, rol=rol, tolerar_error=True)
        ocurrio = r.returncode == 0 and 'ERROR' not in r.stdout
        lineas.append(f"{rol:<18} {'PERMITIDO' if ocurrio else 'DENEGADO':<10} "
                      f"{'PERMITIDO' if permitido else 'DENEGADO':<10} {descripcion}"
                      + ('' if ocurrio else '   → ' + r.stdout.strip().splitlines()[0][:90]))
        lab.comprobar(f'{rol}: {descripcion}', ocurrio == permitido,
                      'permitido' if ocurrio else 'denegado')
    return '\n'.join(lineas) + '\n'


def paso_u5(lab: Lab) -> None:
    import anonimizar_log
    import simulacro_incidente

    lab.titulo('Unidad 5: usuarios, auditoría, roles y permisos')
    transaccion(lab, 'tpi2/u5/01_usuario_autenticacion.sql', 'tpi2/u5/02_auditoria.sql',
                'tpi2/u5/03_usuario_anon.sql')
    # El servidor de sincronización (U8) se instala antes de los roles para que
    # su política de permisos quede incluida en la misma verificación.
    transaccion(lab, 'tpi2/u8/servidor_sync.sql')
    roles = transaccion(lab, 'tpi2/u5/04_roles.sql', variables=variables_claves(lab))
    lab.guardar('u5_01_roles.txt', roles[roles.rfind('rolname'):] if 'rolname' in roles else roles)
    config = lab.psql('-f', 'tpi2/u5/05_config_auditoria.sql').stdout
    lab.guardar('u5_02_config_auditoria.txt', config)
    lab.comprobar('Auditoría del servidor activada',
                  all(x in config for x in ('log_connections', 'log_disconnections', 'log_statement')))

    permisos = lab.psql('-f', 'tpi2/u5/06_verificar_permisos.sql').stdout
    lab.guardar('u5_03_verificacion_permisos.txt', permisos)
    lab.comprobar('Permisos idénticos a la matriz de la spec', 'PERMISOS VERIFICADOS' in permisos,
                  permisos.split('PERMISOS VERIFICADOS:')[-1].splitlines()[0].strip())
    lab.guardar('u5_04_pruebas_por_rol.txt', pruebas_por_rol(lab))

    futuros = lab.sql("""
        BEGIN;
        SET ROLE fs_owner;
        CREATE TABLE public.tabla_futura (dato text);
        CREATE FUNCTION public.funcion_futura() RETURNS integer LANGUAGE sql AS 'SELECT 1';
        CREATE TABLE anon.vista_futura (dato text);
        RESET ROLE;
        SELECT has_table_privilege('rol_soporte', 'public.tabla_futura', 'SELECT') AS soporte_lee_tabla_nueva,
               has_table_privilege('rol_app_escritura', 'public.tabla_futura', 'SELECT') AS app_lee_tabla_nueva,
               has_function_privilege('public', 'public.funcion_futura()', 'EXECUTE') AS public_ejecuta_funcion_nueva,
               has_table_privilege('rol_reportes', 'anon.vista_futura', 'SELECT') AS reportes_lee_anon_nuevo;
        ROLLBACK;
    """)
    lab.guardar('u5_05_privilegios_por_defecto.txt', futuros)
    fila = [l for l in futuros.splitlines() if l.strip().startswith(('t ', 'f '))][0]
    lab.comprobar('Objetos futuros: nadie accede salvo decisión explícita',
                  [c.strip() for c in fila.split('|')] == ['f', 'f', 'f', 't'],
                  'tabla nueva en public: sin acceso; función nueva: sin PUBLIC; objeto nuevo en anon: reportes')

    auditoria_ia = lab.psql('-f', 'tpi2/u5/08_auditoria_seguridad.sql').stdout
    lab.guardar('u5_06_auditoria_seguridad.txt', auditoria_ia)

    # --- Prueba de la auditoría: lectura, inserción, actualización y login fallido.
    marca = lab.marca_log()
    inicio = lab.valor('SELECT clock_timestamp()')
    lab.psql('-c', 'SELECT count(*) FROM public.cliente', rol='soporte_01', app='prueba-auditoria')
    lab.psql('-c', "INSERT INTO public.cliente (correo_electronico, nombre, apellido) "
                   "VALUES ('prueba.auditoria@example.test', 'Prueba', 'Auditoria')",
             rol='app_web', app='prueba-auditoria')
    lab.psql('-c', "UPDATE public.cliente SET nro_telefono = '+54 9 11 5555-7777' "
                   "WHERE correo_electronico = 'prueba.auditoria@example.test'",
             rol='soporte_01', app='prueba-auditoria')
    fallido = lab.psql('-c', 'SELECT 1', rol='soporte_01', clave='clave-equivocada',
                       app='prueba-auditoria', tolerar_error=True)
    lab.comprobar('Login con clave errónea rechazado', 'password authentication failed' in fallido.stdout)
    fragmento = lab.log_desde(marca)
    tabla = lab.sql("SELECT to_char(momento, 'HH24:MI:SS.MS') AS hora, rol_sesion, origen, aplicacion, tabla, "
                    "operacion, antes ->> 'nro_telefono' AS tel_antes, despues ->> 'nro_telefono' AS tel_despues "
                    "FROM auditoria.registro WHERE momento >= :'inicio'::timestamptz ORDER BY id_registro",
                    rol='auditor_01', variables={'inicio': inicio})
    lab.guardar('u5_07_log_auditoria_prueba.txt',
                'FRAGMENTO DEL LOG DEL SERVIDOR (datos sintéticos de laboratorio)\n\n' + fragmento
                + '\nAUDITORIA POR FILA (auditoria.registro, leída con el rol auditor_01)\n\n' + tabla)
    for esperado in ('connection authorized', 'statement: SELECT count(*) FROM public.cliente',
                     'statement: INSERT INTO public.cliente', 'statement: UPDATE public.cliente',
                     'password authentication failed', 'disconnection'):
        lab.comprobar(f'El log registra: {esperado}', esperado in fragmento)

    # --- Simulacro de acceso indebido.
    lab.titulo('Unidad 5: simulacro de acceso indebido')
    marca = lab.marca_log()
    inicio = lab.valor('SELECT clock_timestamp()')
    pasos = simulacro_incidente.ejecutar(lab)
    crudo = lab.log_desde(marca)
    intentos = lab.sql("SELECT to_char(momento, 'YYYY-MM-DD HH24:MI:SS.MS') AS momento, correo, exito, motivo, "
                       "rol_sesion, origen, aplicacion FROM auditoria.intento_login "
                       "WHERE momento >= :'inicio'::timestamptz ORDER BY id_intento",
                       rol='auditor_01', variables={'inicio': inicio})
    alerta = lab.sql('SELECT * FROM auditoria.v_alerta_fuerza_bruta', rol='auditor_01')
    registro = lab.sql("SELECT to_char(momento, 'YYYY-MM-DD HH24:MI:SS.MS') AS momento, rol_sesion, origen, "
                       "aplicacion, tabla, operacion, antes ->> 'id_cliente' AS id_cliente, "
                       "antes ->> 'nro_telefono' AS antes, despues ->> 'nro_telefono' AS despues "
                       "FROM auditoria.registro WHERE momento >= :'inicio'::timestamptz "
                       "AND tabla = 'public.cliente' ORDER BY id_registro",
                       rol='auditor_01', variables={'inicio': inicio})
    completo = ('=== A. LOG DEL SERVIDOR POSTGRESQL ===\n' + crudo
                + '\n=== B. TABLA auditoria.intento_login ===\n' + intentos
                + '\n=== C. VISTA auditoria.v_alerta_fuerza_bruta ===\n' + alerta
                + '\n=== D. TABLA auditoria.registro (cambios sobre cliente) ===\n' + registro)
    nombres = lab.valor("SELECT string_agg(DISTINCT n, E'\\n') FROM (SELECT nombre AS n FROM usuario "
                        "UNION SELECT apellido FROM usuario UNION SELECT nombre FROM cliente "
                        "UNION SELECT apellido FROM cliente) AS x").split('\n')
    anonimo, cuenta = anonimizar_log.anonimizar(completo, nombres)
    lab.comprobar('Log del simulacro sin datos identificables', not anonimizar_log.restos(anonimo), str(cuenta))
    lab.guardar('u5_08_log_simulacro_anonimizado.txt', anonimo)
    lab.guardar('u5_09_simulacro_pasos.txt', '\n'.join(
        f"{p['etapa']:<16} {p['obtenido']:<10} (previsto {p['esperado']:<9}) {p['accion']}"
        + (f"\n{'':<16} {p['salida'][:150]}" if p['salida'] else '') for p in pasos) + '\n')
    escalamientos = [p for p in pasos if p['etapa'] == '5-escalamiento']
    lab.comprobar('Todos los intentos de escalamiento fallaron',
                  all(p['obtenido'] == 'DENEGADO' for p in escalamientos), f'{len(escalamientos)} intentos')
    lab.comprobar('La alerta de fuerza bruta detecta el ataque', 'usuario3@foodstore.example' in alerta)

    # --- Contención propuesta, probada en el laboratorio.
    contencion = transaccion(lab, 'tpi2/u5/09_contencion.sql', tolerar_error=False, variables={
        'rol_comprometido': 'soporte_01', 'correo_victima': simulacro_incidente.VICTIMA, 'desde': inicio})
    lab.guardar('u5_10_contencion.txt', anonimizar_log.anonimizar(contencion, nombres)[0])
    bloqueado = lab.psql('-c', 'SELECT 1', rol='soporte_01', tolerar_error=True)
    lab.comprobar('Tras la contención soporte_01 no puede conectarse',
                  'not permitted to log in' in bloqueado.stdout)
    telefono = lab.valor(f'SELECT nro_telefono FROM cliente WHERE id_cliente = {simulacro_incidente.CLIENTE_MODIFICADO}')
    lab.comprobar('El teléfono alterado fue restaurado desde la auditoría',
                  telefono != simulacro_incidente.TELEFONO_FALSO, 'valor original recuperado')
    viejo = lab.valor("SELECT public.fn_autenticar(:'c', :'p')", rol='app_web',
                      variables={'c': simulacro_incidente.VICTIMA, 'p': simulacro_incidente.clave_laboratorio(3)})
    lab.comprobar('La clave adivinada ya no sirve', viejo == 'f')
    # Cierre del simulacro: se rehabilita el rol con una clave nueva.
    lab.sql("BEGIN; SET LOCAL log_statement = 'none'; ALTER ROLE soporte_01 LOGIN PASSWORD :'clave'; COMMIT;",
            variables={'clave': lab.claves['soporte_01']})

    # --- Anonimización: equivalencia de agregados.
    lab.sql('REFRESH MATERIALIZED VIEW anon.usuario_anon; REFRESH MATERIALIZED VIEW anon.cliente_anon; '
            'REFRESH MATERIALIZED VIEW anon.pedido_anon;')
    equivalencia = lab.sql("""
        \\echo 'Consulta sobre la tabla REAL (public.usuario)'
        SELECT rol_aplicacion, date_trunc('month', fecha_alta AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
               count(*) AS usuarios, count(*) FILTER (WHERE activo) AS activos
        FROM public.usuario GROUP BY 1, 2 ORDER BY 1, 2;
        \\echo 'Consulta equivalente sobre la copia ANONIMA (anon.usuario_anon)'
        SELECT rol_aplicacion, mes_alta, count(*) AS usuarios, count(*) FILTER (WHERE activo) AS activos
        FROM anon.usuario_anon GROUP BY 1, 2 ORDER BY 1, 2;
        \\echo 'Diferencias entre ambas (0 filas = equivalentes)'
        SELECT * FROM seguridad.v_equivalencia_usuario;
        \\echo 'Los seudónimos son uno a uno'
        SELECT (SELECT count(*) FROM public.cliente) AS clientes_reales,
               (SELECT count(DISTINCT cliente_anon) FROM anon.cliente_anon) AS seudonimos_distintos,
               (SELECT count(*) FROM anon.pedido_anon a JOIN anon.cliente_anon c USING (cliente_anon)) AS pedidos_enlazados,
               (SELECT count(*) FROM public.pedido) AS pedidos_reales;
        \\echo 'Muestra de lo que ve un analista (ningún dato identificable)'
        SELECT * FROM anon.usuario_anon ORDER BY 1 LIMIT 3;
    """)
    lab.guardar('u5_11_equivalencia_anonimizacion.txt', equivalencia)
    lab.comprobar('Agregados reales y anónimos equivalentes',
                  lab.valor('SELECT count(*) FROM seguridad.v_equivalencia_usuario') == '0')


# ----------------------------------------------------------------------------- U6
def powershell(lab: Lab, script: str, *args: str, rol: str | None = None,
               tolerar_error: bool = False, con_pg: bool = True) -> tuple[int, str, dict]:
    """Ejecuta un script de tpi2/u6 y devuelve (código, salida, RESULTADO json)."""
    cmd = ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
           '-File', str(TPI2 / 'u6' / script)]
    if con_pg:
        cmd += ['-PgBin', str(lab.pg_bin), '-Puerto', lab.port]
    cmd += list(args)
    r = subprocess.run(cmd, cwd=REPO, env=lab.entorno(rol), stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
    resultado = {}
    for linea in r.stdout.splitlines():
        if linea.startswith('RESULTADO '):
            resultado = json.loads(linea[len('RESULTADO '):])
    if r.returncode != 0 and not tolerar_error:
        raise RuntimeError(f'{script} terminó con código {r.returncode}:\n{r.stdout[-3000:]}')
    return r.returncode, r.stdout, resultado


def paso_u6(lab: Lab) -> None:
    lab.titulo('Unidad 6: plan de mantenimiento automatizado')
    lab.psql('-f', 'tpi2/u6/00_instalar.sql')
    respaldos = lab.carpeta / 'respaldos'
    registros = lab.carpeta / 'registros'

    # --- Tareas rutinarias: limpieza, estadísticas, copias derivadas, integridad.
    _, salida, _ = powershell(lab, 'mantenimiento.ps1', '-Base', lab.base, '-Registros', str(registros))
    log_mant = sorted(registros.glob('mantenimiento_*.log'))[-1].read_text(encoding='utf-8-sig')
    lab.guardar('u6_01_mantenimiento.txt', log_mant)
    lab.comprobar('Mantenimiento semanal ejecutado', 'MANTENIMIENTO CORRECTO' in salida)
    lab.comprobar('Integridad física y lógica verificada', 'INTEGRIDAD VERIFICADA' in log_mant)

    # --- Respaldo con el rol de solo lectura.
    _, salida, respaldo = powershell(lab, 'respaldo.ps1', '-Base', lab.base, '-Destino', str(respaldos),
                                     rol='operador_respaldo')
    lab.guardar('u6_02_respaldo.txt', salida)
    lab.comprobar('Respaldo diario creado y verificado', respaldo.get('exito') is True,
                  f"{respaldo.get('bytes')} bytes, {respaldo.get('objetos')} objetos, {respaldo.get('segundos')} s")
    dump = Path(respaldo['dump'])
    huella_respaldo = lab.huella()
    momento_respaldo = datetime.now()

    # Un respaldo que falla no deja un archivo que parezca válido.
    codigo, salida, malo = powershell(lab, 'respaldo.ps1', '-Base', lab.base,
                                      '-Destino', str(respaldos / 'fallido'),
                                      '-Usuario', 'rol_inexistente', rol='operador_respaldo', tolerar_error=True)
    lab.comprobar('Respaldo fallido: código de error y sin archivo',
                  codigo == 1 and malo.get('exito') is False
                  and not list((respaldos / 'fallido').glob('*.dump')))

    # --- Restauración de prueba en una base temporal.
    _, salida, _ = powershell(lab, 'prueba_restauracion.ps1', '-Base', lab.base, '-Origen', str(respaldos))
    lab.guardar('u6_03_prueba_restauracion.txt', salida)
    lab.comprobar('Restauración de prueba verificada',
                  'INTEGRIDAD VERIFICADA' in salida and '"exito":true' in salida)
    lab.comprobar('La base temporal de prueba fue eliminada',
                  lab.valor("SELECT count(*) FROM pg_database WHERE datname LIKE 'restauracion_prueba_%'",
                            base='postgres') == '0')

    # Un respaldo alterado se detecta antes de restaurar.
    alterado = respaldos / 'alterado.dump'
    datos = bytearray(dump.read_bytes())
    datos[len(datos) // 2] ^= 0xFF
    alterado.write_bytes(bytes(datos))
    (respaldos / 'alterado.dump.sha256').write_text((respaldos / (dump.name + '.sha256')).read_text())
    codigo, salida, _ = powershell(lab, 'restaurar.ps1', '-Dump', str(alterado), '-Modo', 'Prueba',
                                   '-BaseDestino', 'no_debe_crearse', tolerar_error=True)
    lab.comprobar('Respaldo corrupto rechazado por SHA-256', codigo == 1 and 'SHA-256 distinto' in salida)
    alterado.unlink()
    (respaldos / 'alterado.dump.sha256').unlink()

    # --- Programación (modo simulación: no registra tareas en este equipo).
    _, salida, _ = powershell(lab, 'programar_tareas.ps1', '-Base', lab.base, '-PgBin', str(lab.pg_bin),
                              '-Puerto', lab.port, '-PgPassFile', 'C:\\ruta\\segura\\pgpass.conf',
                              con_pg=False)
    lab.guardar('u6_04_programacion.txt', salida)
    lab.comprobar('Plan de tareas programadas definido', salida.count('[simulacion]') == 3)

    # --- Simulacro de desastre, contra reloj.
    lab.titulo('Unidad 6: simulacro de desastre')
    objetivo_rto = 15 * 60
    # Actividad posterior al último respaldo: es lo que se va a perder.
    for linea in ('[{"id_producto": 1, "cantidad": 1}]', '[{"id_producto": 2, "cantidad": 3}]',
                  '[{"id_producto": 3, "cantidad": 2}, {"id_producto": 4, "cantidad": 1}]'):
        lab.sql(f"CALL tpi_registrar_pedido(12, 'TARJETA', '{linea}'::jsonb, NULL);", rol='app_web')
    lab.sql('UPDATE producto SET precio_lista = precio_lista + 100 WHERE id_producto = 5;', rol='admin_datos')
    antes = lab.valor("SELECT (SELECT count(*) FROM pedido) || '|' || "
                      "(SELECT precio_lista FROM producto WHERE id_producto = 5)")
    pedidos_antes, precio_antes = antes.split('|')

    marca = lab.marca_log()
    linea_tiempo = []
    t0 = time.perf_counter()
    momento_desastre = datetime.now()

    def hito(texto: str) -> None:
        linea_tiempo.append((round(time.perf_counter() - t0, 2), texto))
        print(f'  t+{linea_tiempo[-1][0]:>7.2f} s  {texto}', flush=True)

    lab.psql('-c', f'DROP DATABASE "{lab.base}" WITH (FORCE)', base='postgres')
    hito('DESASTRE: la base fue eliminada (DROP DATABASE)')
    caida = lab.psql('-Atc', 'SELECT count(*) FROM tp5_productos_vigentes', rol='app_web', tolerar_error=True)
    lab.comprobar('La aplicación detecta la caída', 'does not exist' in caida.stdout)
    hito('Detección: la aplicación no puede conectarse')

    _, salida, rest = powershell(lab, 'restaurar.ps1', '-Dump', str(dump), '-Modo', 'Siniestro')
    for fase, segundos in rest['fases'].items():
        linea_tiempo.append((round(time.perf_counter() - t0, 2), f'  fase {fase}: {segundos} s'))
    hito('Base restaurada desde el último respaldo e integridad verificada')

    lab.comprobar('La base restaurada es idéntica al momento del respaldo', lab.huella() == huella_respaldo)
    hito('Contenido comparado con la huella tomada al respaldar')
    permisos = lab.psql('-f', 'tpi2/u5/06_verificar_permisos.sql').stdout
    lab.comprobar('Permisos restaurados, incluidos los de nivel base', 'PERMISOS VERIFICADOS' in permisos)
    hito('Permisos verificados contra la matriz')
    catalogo = lab.valor('SELECT count(*) FROM tp5_productos_vigentes', rol='app_web')
    lab.sql("BEGIN; CALL tpi_registrar_pedido(12, 'EFECTIVO', '[{\"id_producto\": 1, \"cantidad\": 1}]'::jsonb, NULL); ROLLBACK;",
            rol='app_web')
    lab.comprobar('La aplicación vuelve a operar', int(catalogo) > 0, f'{catalogo} productos en catálogo')
    hito('Prueba de humo: la aplicación lee el catálogo y registra un pedido')
    rto = time.perf_counter() - t0

    despues = lab.valor("SELECT (SELECT count(*) FROM pedido) || '|' || "
                        "(SELECT precio_lista FROM producto WHERE id_producto = 5)")
    pedidos_despues, precio_despues = despues.split('|')
    rpo = (momento_desastre - momento_respaldo).total_seconds()
    log_servidor = lab.log_desde((marca[0], 0))
    rastro_precio = 'UPDATE producto SET precio_lista = precio_lista + 100 WHERE id_producto = 5' in log_servidor
    rastro_pedidos = "tpi_registrar_pedido(12, 'TARJETA'" in log_servidor

    lab.comprobar('RTO dentro del objetivo de 15 minutos', rto <= objetivo_rto, f'{rto:.1f} s')
    perdidos = int(pedidos_antes) - int(pedidos_despues)
    lab.comprobar('Pérdida de datos acotada a lo posterior al respaldo',
                  perdidos == 3 and precio_antes != precio_despues,
                  f'{perdidos} pedidos y 1 cambio de precio')
    informe = {
        'fecha': momento_desastre.strftime('%Y-%m-%d %H:%M:%S'),
        'base': lab.base, 'respaldo_utilizado': dump.name, 'respaldo_bytes': respaldo['bytes'],
        'respaldo_termino': momento_respaldo.strftime('%Y-%m-%d %H:%M:%S'),
        'rto_objetivo_segundos': objetivo_rto, 'rto_observado_segundos': round(rto, 2),
        'rpo_objetivo_segundos': 24 * 3600, 'rpo_observado_segundos': round(rpo, 2),
        'fases_restauracion_segundos': rest['fases'],
        'pedidos_antes_del_desastre': int(pedidos_antes), 'pedidos_tras_restaurar': int(pedidos_despues),
        'pedidos_perdidos': perdidos,
        'cambio_de_precio_perdido': {'antes_del_desastre': precio_antes, 'tras_restaurar': precio_despues},
        'rastro_en_log_del_servidor': {'cambio_de_precio': rastro_precio, 'pedidos': rastro_pedidos},
        'linea_de_tiempo': [{'t_segundos': t, 'hito': h} for t, h in linea_tiempo],
    }
    lab.guardar('u6_05_simulacro_desastre.json', json.dumps(informe, ensure_ascii=False, indent=2) + '\n')
    lab.guardar('u6_05_simulacro_desastre.txt',
                f"SIMULACRO DE DESASTRE - {informe['fecha']}\n"
                f"Respaldo utilizado: {dump.name} ({respaldo['bytes']} bytes), terminado {informe['respaldo_termino']}\n\n"
                + '\n'.join(f't+{t:>7.2f} s  {h}' for t, h in linea_tiempo)
                + f"\n\nRTO observado: {rto:.2f} s (objetivo {objetivo_rto} s)\n"
                  f"RPO observado: {rpo:.2f} s (objetivo {24 * 3600} s)\n"
                  f"Pedidos: {pedidos_antes} antes del desastre, {pedidos_despues} tras restaurar "
                  f"({perdidos} perdidos)\n"
                  f"Precio del producto 5: {precio_antes} antes, {precio_despues} tras restaurar\n"
                  f"Rastro en el log del servidor: cambio de precio={rastro_precio}, pedidos={rastro_pedidos}\n\n"
                + salida)


# ----------------------------------------------------------------------------- U7
def paso_u7(lab: Lab) -> None:
    lab.titulo('Unidad 7: modelo documental en MongoDB y comparación')
    base_mongo = lab.base                       # misma denominación que la base relacional
    uri = lab.mongo_uri.rstrip('/') + '/' + base_mongo
    archivo = lab.carpeta / 'u7_pedidos.ndjson'

    exportado = lab.psql('-At', '-f', 'tpi2/u7/01_exportar_pedidos.sql', '-o', str(archivo))
    documentos = sum(1 for _ in archivo.open(encoding='utf-8'))
    pedidos_con_lineas = lab.valor('SELECT count(DISTINCT id_pedido) FROM detalle_pedido')
    lab.comprobar('Exportación: un documento por pedido con líneas', str(documentos) == pedidos_con_lineas,
                  f'{documentos} documentos')

    version = lab.mongo('--eval', 'db.version()').stdout.strip()
    lab.comprobar('MongoDB disponible', bool(version), version)
    creacion = subprocess.run([lab.mongosh, uri, '--quiet', str(REPO / 'tpi2/u7/02_crear_coleccion.js')],
                              cwd=REPO, capture_output=True, text=True, encoding='utf-8')
    if creacion.returncode != 0:
        raise RuntimeError(creacion.stdout + creacion.stderr)
    ruta = str(archivo).replace('\\', '/')
    carga = subprocess.run([lab.mongosh, uri, '--quiet', '--eval', f"const ARCHIVO='{ruta}'",
                            str(REPO / 'tpi2/u7/03_cargar_pedidos.js')],
                           cwd=REPO, capture_output=True, text=True, encoding='utf-8')
    if carga.returncode != 0:
        raise RuntimeError(carga.stdout + carga.stderr)
    lab.guardar('u7_01_carga.txt', f'MongoDB {version}\n\n' + creacion.stdout + '\n' + carga.stdout)
    lab.comprobar('Carga completa en MongoDB, validador aceptó todos los documentos',
                  f'en_coleccion: {documentos}' in carga.stdout)
    archivo.unlink()                            # el volcado no se versiona: se regenera en cada corrida

    def mongo_json(script: str) -> dict:
        r = subprocess.run([lab.mongosh, uri, '--quiet', str(REPO / script)], cwd=REPO,
                           capture_output=True, text=True, encoding='utf-8')
        if r.returncode != 0:
            raise RuntimeError(r.stdout + r.stderr)
        return json.loads(r.stdout.strip().splitlines()[-1])

    m = mongo_json('tpi2/u7/04_consultas.js')
    p = json.loads(lab.psql('-At', '-f', 'tpi2/u7/05_consultas.sql').stdout.strip().splitlines()[-1])
    planes_pg = lab.sql("""
        EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
        SELECT p.id_pedido, d.* FROM pedido p JOIN cliente c ON c.id_cliente = p.cliente_id
        JOIN detalle_pedido d ON d.id_pedido = p.id_pedido WHERE p.id_pedido = 1500;
        EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
        SELECT id_pedido FROM detalle_pedido WHERE id_producto = 1 ORDER BY id_pedido;
    """)
    filas = [f"{'consulta':<30} {'coinciden':<9} {'PostgreSQL ms':>13} {'MongoDB ms':>11}  plan MongoDB"]
    for nombre in sorted(m['consultas']):
        rm, rp = m['consultas'][nombre], p['consultas'][nombre]
        iguales = rm['resultado'] == rp['resultado']
        filas.append(f"{nombre:<30} {'SÍ' if iguales else 'NO':<9} {rp['mediana_ms']:>13} {rm['mediana_ms']:>11}  "
                     f"{rm['plan'].get('etapas', '')} (examinó {rm['plan'].get('documentos_examinados', '?')} docs)")
        lab.comprobar(f'Mismo resultado en ambos motores: {nombre}', iguales)
    lab.guardar('u7_02_comparacion_consultas.txt',
                'Mediana de 30 ejecuciones medida dentro de cada motor (sin red ni arranque del cliente).\n'
                f'Documentos en la colección: {m["coleccion"]}\n\n' + '\n'.join(filas)
                + '\n\nPlanes PostgreSQL de C1 y C3\n' + planes_pg)
    lab.guardar('u7_03_resultados_mongodb.json', json.dumps(m, ensure_ascii=False, indent=1) + '\n')
    lab.guardar('u7_04_resultados_postgresql.json', json.dumps(p, ensure_ascii=False, indent=1) + '\n')

    v = mongo_json('tpi2/u7/06_pruebas_validador.js')
    lab.guardar('u7_05_validador_y_duplicacion.json', json.dumps(v, ensure_ascii=False, indent=1) + '\n')
    for prueba in v['pruebas']:
        esperado_rechazo = prueba['prueba'] != 'documento válido (control)'
        if prueba['prueba'] == 'id de pedido duplicado':
            lab.comprobar('Validador: id de pedido duplicado', prueba.get('codigo') == 11000, 'E11000')
        else:
            lab.comprobar(f"Validador: {prueba['prueba']}", prueba['rechazado'] == esperado_rechazo,
                          'rechazado' if prueba['rechazado'] else 'aceptado')
    lab.comprobar('Duplicación medida y revertida', v['documentos_finales'] == documentos,
                  f"un cambio de apellido toca {v['duplicacion']['documentos_a_modificar_por_un_cambio_de_apellido']} "
                  'documentos contra 1 fila en PostgreSQL')


# ----------------------------------------------------------------------------- U8
def servidor_movil(lab: Lab, puerto: str | None = None, demora: float = 0.0):
    """Devuelve ejecutar_sql(texto) para la tablet: psql con el rol tablet_feria.
    puerto distinto simula la red caída; demora mantiene abierta la transacción."""
    import cliente_movil

    def ejecutar(texto: str) -> str:
        if demora:
            texto = f'BEGIN;\n{texto}\nSELECT pg_sleep({demora});\nCOMMIT;'
        env = lab.entorno('tablet_feria', app='tablet-feria')
        if puerto:
            env['PGPORT'] = puerto
        r = subprocess.run([lab.exe('psql'), '-X', '-Atq', '-v', 'ON_ERROR_STOP=1', '-d', lab.base, '-f', '-'],
                           input=texto, cwd=REPO, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, encoding='utf-8', errors='replace')
        if r.returncode != 0:
            if 'connection to server' in r.stdout or 'Connection refused' in r.stdout:
                raise cliente_movil.SinConexion('Servidor no disponible')
            raise RuntimeError(r.stdout)
        return next(l for l in r.stdout.splitlines() if l.strip())
    return ejecutar


def paso_u8(lab: Lab) -> None:
    import sqlite3
    import threading
    import cliente_movil
    from cliente_movil import Tablet, SinConexion, SnapshotInvalido

    lab.titulo('Unidad 8: base SQLite de la tablet y sincronización con PostgreSQL')
    lab.comprobar('SQLite con tablas STRICT (3.37+)', sqlite3.sqlite_version_info >= (3, 37), sqlite3.sqlite_version)
    online, offline = servidor_movil(lab), servidor_movil(lab, puerto='1')
    carpeta = lab.carpeta / 'u8_tablets'
    carpeta.mkdir(exist_ok=True)
    t1 = Tablet(carpeta / 'tablet-01.db', 'tablet-01', online)
    t2 = Tablet(carpeta / 'tablet-02.db', 'tablet-02', online)
    casos: list[str] = []

    def caso(codigo: str, descripcion: str, condicion: bool, detalle: str = '') -> None:
        casos.append(f"{codigo:<4} {'OK' if condicion else 'FALLA':<6} {descripcion}" + (f'\n{"":<11} {detalle}' if detalle else ''))
        lab.comprobar(f'{codigo} {descripcion}', condicion, detalle)

    ids = [int(x) for x in lab.valor(
        'SELECT string_agg(id::text, \',\' ORDER BY id) FROM (SELECT id FROM sync.v_snapshot_movil '
        'WHERE disponible AND stock >= 20 ORDER BY id LIMIT 5) x').split(',')]
    A, B, C, D, E = ids
    stock = lambda p: int(lab.valor(f'SELECT stock FROM producto WHERE id_producto = {p}'))
    precio = lambda p: lab.valor(f'SELECT precio_lista FROM producto WHERE id_producto = {p}')
    pedidos_servidor = lambda: int(lab.valor('SELECT count(*) FROM pedido'))

    v1 = t1.descargar_catalogo()
    t2.descargar_catalogo()
    productos_locales = len(t1.catalogo())
    lab.comprobar('Instantánea descargada en SQLite', productos_locales > 0,
                  f'versión {v1}, {productos_locales} productos disponibles')
    datos_personales = lab.valor("SELECT count(*) FROM information_schema.columns WHERE table_schema = 'sync' "
                                 "AND table_name = 'v_snapshot_movil' AND column_name ~ '(correo|telefono|cliente|apellido)'")
    caso('C0', 'La instantánea no contiene datos personales', datos_personales == '0',
         'columnas: id, nombre, categoria, precio_centavos, stock, disponible, eliminado')

    # C11: restricciones locales.
    rechazos = 0
    b_ok = t1.crear_borrador('EFECTIVO', [(C, 1)])
    for sql, args in (('INSERT INTO item_borrador VALUES (?, ?, 0, 100)', (b_ok, D)),
                      ('INSERT INTO item_borrador VALUES (?, 999999, 1, 100)', (b_ok,)),
                      ("INSERT INTO pedido_borrador (id_local, forma_pago, creado_en) VALUES ('no-es-uuid', 'EFECTIVO', 'x')", ()),
                      ("INSERT INTO pedido_borrador (id_local, forma_pago, creado_en) VALUES (?, 'CHEQUE', 'x')", (str(uuid.uuid4()),)),
                      ("INSERT INTO producto_cache VALUES (5000, 'x', 'y', 'caro', 1, 1, 0, 1)", ())):
        try:
            t1.db.execute(sql, args)
        except sqlite3.IntegrityError:
            rechazos += 1
    caso('C11', 'SQLite rechaza datos inválidos (CHECK, FK, STRICT)', rechazos == 5,
         f'{rechazos}/5 inserciones inválidas rechazadas: cantidad 0, producto inexistente, uuid mal formado, '
         'forma de pago inexistente, texto en columna INTEGER')
    t1.db.execute('DELETE FROM item_borrador WHERE id_local = ?', (b_ok,))
    t1.db.execute('DELETE FROM pedido_borrador WHERE id_local = ?', (b_ok,))

    # C9: un borrador sin ítems no se envía (corrección R1 de la revisión de TP8).
    vacio = str(uuid.uuid4())
    t1.db.execute("INSERT INTO pedido_borrador (id_local, forma_pago, creado_en) VALUES (?, 'EFECTIVO', ?)",
                  (vacio, cliente_movil.ahora()))
    try:
        t1.encolar(vacio)
        bloqueado = False
    except sqlite3.IntegrityError as e:
        bloqueado = 'no tiene ítems' in str(e)
    caso('C9', 'Un borrador vacío no puede encolarse', bloqueado)
    t1.db.execute('DELETE FROM pedido_borrador WHERE id_local = ?', (vacio,))

    # C10: una instantánea vacía no borra el catálogo (corrección R3).
    try:
        t1.aplicar_snapshot({'servidor_en': cliente_movil.ahora(), 'productos': []})
        rechazada = False
    except SnapshotInvalido:
        rechazada = True
    caso('C10', 'Una instantánea vacía no reemplaza el catálogo',
         rechazada and len(t1.catalogo()) == productos_locales, f'catálogo intacto: {productos_locales} productos')

    # C1: catálogo sin conexión.
    t1.ejecutar_sql = offline
    try:
        t1.descargar_catalogo()
        sin_red = False
    except SinConexion:
        sin_red = True
    caso('C1', 'Sin conexión el catálogo local sigue consultable', sin_red and len(t1.catalogo()) == productos_locales,
         f'descarga fallida, {len(t1.catalogo())} productos visibles')

    # Borradores armados con la instantánea v1.
    stock_E = stock(E)
    b_precio = t1.crear_borrador('EFECTIVO', [(A, 1)])
    b_baja = t1.crear_borrador('TARJETA', [(B, 1)])
    b_normal = t1.crear_borrador('TRANSFERENCIA', [(C, 2)])
    b_stock = t1.crear_borrador('EFECTIVO', [(E, stock_E + 1)])
    precio_A_visto = t1.db.execute('SELECT precio_centavos_visto FROM item_borrador WHERE id_local = ?',
                                   (b_precio,)).fetchone()[0]

    # Mientras tanto, en el servidor (cambios hechos por administración, no por la tablet).
    lab.sql(f'UPDATE producto SET precio_lista = precio_lista + 150 WHERE id_producto = {A};', rol='admin_datos')
    lab.sql(f'CALL tpi_baja_producto({B});', rol='admin_datos')

    # C7: se intenta sincronizar sin conexión.
    recibidas_antes = lab.valor('SELECT count(*) FROM sync.solicitud')
    solicitudes = {b: t1.encolar(b) for b in (b_precio, b_baja, b_normal, b_stock)}
    r = t1.sincronizar()
    pendientes = t1.db.execute("SELECT count(*) FROM cola_sync WHERE estado = 'PENDIENTE'").fetchone()[0]
    intentadas = t1.db.execute("SELECT count(*) FROM cola_sync WHERE intentos = 1 AND ultimo_error IS NOT NULL").fetchone()[0]
    en_servidor = lab.valor('SELECT count(*) FROM sync.solicitud')
    caso('C7', 'Sin conexión las solicitudes quedan pendientes y no se pierden',
         r['sin_conexion'] and pendientes == 4 and intentadas == 1 and en_servidor == recibidas_antes,
         f'{pendientes} pendientes; la primera falló por red y la sincronización se detuvo; el servidor no recibió nada')

    # Vuelve la conexión.
    t1.ejecutar_sql = online
    stock_C, pedidos_antes = stock(C), pedidos_servidor()
    r = t1.sincronizar()
    lab.comprobar('C7 al reconectar se envían todas las pendientes', r['enviadas'] == 4 and not r['sin_conexion'])
    est = {b: t1.estado(s) for b, s in solicitudes.items()}
    resp = {b: json.loads(e['respuesta']) for b, e in est.items()}

    caso('C5', 'Pedido sin cambios: el servidor lo aplica',
         est[b_normal]['estado'] == 'APLICADO' and stock(C) == stock_C - 2,
         f"pedido {resp[b_normal]['id_pedido']} CONFIRMADO; stock de {C}: {stock_C} -> {stock(C)}")
    caso('C3', 'Stock insuficiente: rechazado y sin efectos',
         est[b_stock]['estado'] == 'RECHAZADO' and resp[b_stock]['problemas'][0]['motivo'] == 'STOCK_INSUFICIENTE'
         and stock(E) == stock_E, json.dumps(resp[b_stock]['problemas'], ensure_ascii=False))
    caso('C4', 'Producto dado de baja después de copiar el catálogo: rechazado',
         est[b_baja]['estado'] == 'RECHAZADO' and resp[b_baja]['problemas'][0]['motivo'] == 'PRODUCTO_DADO_DE_BAJA',
         json.dumps(resp[b_baja]['problemas'], ensure_ascii=False))
    caso('C2', 'Precio cambiado en el servidor: conflicto detectado',
         est[b_precio]['estado'] == 'CONFLICTO' and resp[b_precio]['problemas'][0]['motivo'] == 'PRECIO_CAMBIADO',
         json.dumps(resp[b_precio]['problemas'], ensure_ascii=False))
    lab.comprobar('Solo el pedido aplicado creó una venta', pedidos_servidor() == pedidos_antes + 1)

    # Resolución de C2: gana el servidor; la persona acepta el precio nuevo y se reenvía con otro UUID.
    t1.descargar_catalogo()
    nueva = t1.aceptar_precios_y_reenviar(b_precio)
    respuesta = t1.enviar(nueva)
    precio_vendido = lab.valor(f"SELECT precio_unitario FROM detalle_pedido WHERE id_pedido = {respuesta['id_pedido']}")
    caso('C2', 'Conflicto resuelto: precio del servidor aceptado y pedido aplicado',
         respuesta['estado'] == 'APLICADO' and nueva != solicitudes[b_precio] and precio_vendido == precio(A),
         f"visto {precio_A_visto / 100:.2f}, vendido {precio_vendido}; solicitud original conserva CONFLICTO")

    lapida = t1.db.execute('SELECT disponible, eliminado FROM producto_cache WHERE id = ?', (B,)).fetchone()
    caso('C4', 'La baja llega como lápida: oculta del catálogo, fila conservada',
         tuple(lapida) == (0, 1) and B not in [p['id'] for p in t1.catalogo()]
         and t1.db.execute('SELECT count(*) FROM item_borrador WHERE producto_id = ?', (B,)).fetchone()[0] == 1)

    # C6: la respuesta se pierde; la tablet reenvía el mismo UUID.
    b_reenvio = t1.crear_borrador('EFECTIVO', [(C, 1)])
    s_reenvio = t1.encolar(b_reenvio)
    pedidos_antes = pedidos_servidor()
    t1.enviar(s_reenvio, perder_respuesta=True)
    sigue_pendiente = t1.estado(s_reenvio)['estado'] == 'PENDIENTE'
    t1.sincronizar()
    final = json.loads(t1.estado(s_reenvio)['respuesta'])
    caso('C6', 'Respuesta perdida y reenvío del mismo UUID: una sola venta',
         sigue_pendiente and final['duplicada'] is True and pedidos_servidor() == pedidos_antes + 1
         and t1.estado(s_reenvio)['intentos'] == 2,
         f"2 envíos, 1 pedido ({final['id_pedido']}); el servidor contestó duplicada=true")

    # C8: dos tablets compiten por las últimas unidades.
    lab.sql(f'UPDATE producto SET stock = 3 WHERE id_producto = {D};', rol='admin_datos')
    t1.descargar_catalogo()
    t2.descargar_catalogo()
    s1 = t1.encolar(t1.crear_borrador('EFECTIVO', [(D, 2)]))
    s2 = t2.encolar(t2.crear_borrador('TARJETA', [(D, 2)]))
    t1.ejecutar_sql = servidor_movil(lab, demora=1.5)      # la primera transacción tarda en confirmar
    tiempos = {}

    def enviar(tablet, solicitud, clave):
        inicio = time.perf_counter()
        tablet.enviar(solicitud)
        tiempos[clave] = time.perf_counter() - inicio

    h1 = threading.Thread(target=enviar, args=(t1, s1, 't1'))
    h1.start()
    time.sleep(0.4)
    enviar(t2, s2, 't2')
    h1.join()
    t1.ejecutar_sql = online
    e1, e2 = t1.estado(s1)['estado'], t2.estado(s2)['estado']
    caso('C8', 'Dos tablets por las últimas unidades: una aplica, la otra espera y es rechazada',
         e1 == 'APLICADO' and e2 == 'RECHAZADO' and stock(D) == 1 and tiempos['t2'] > 0.8,
         f"tablet-01 {e1}, tablet-02 {e2} tras esperar {tiempos['t2']:.2f} s el bloqueo; stock final {stock(D)}")

    # Controles finales.
    for t in (t1, t2):
        chequeo, fk = t.integridad()
        lab.comprobar(f'{t.dispositivo}: PRAGMA integrity_check y foreign_key_check', chequeo == 'ok' and not fk)
    servidor = lab.sql("""
        SELECT estado, count(*) AS solicitudes, count(id_pedido) AS con_pedido FROM sync.solicitud GROUP BY 1 ORDER BY 1;
        SELECT count(*) AS solicitudes_sin_resolver FROM sync.solicitud WHERE estado = 'EN_PROCESO';
        SELECT s.dispositivo, left(s.solicitud_uuid::text, 8) AS solicitud, s.estado, s.id_pedido, p.estado AS estado_pedido,
               s.respuesta -> 'problemas' AS problemas
        FROM sync.solicitud s LEFT JOIN pedido p USING (id_pedido) ORDER BY s.recibida_en;
    """)
    aplicadas = lab.valor("SELECT count(*) FROM sync.solicitud WHERE estado = 'APLICADO'")
    con_pedido = lab.valor('SELECT count(DISTINCT id_pedido) FROM sync.solicitud')
    lab.comprobar('Servidor: cada solicitud aplicada tiene exactamente un pedido', aplicadas == con_pedido,
                  f'{aplicadas} aplicadas, {con_pedido} pedidos')
    directo = lab.psql('-f', '-', rol='tablet_feria', tolerar_error=True,
                       entrada="CALL public.tpi_registrar_pedido(1, 'EFECTIVO', '[{\"id_producto\": 1, \"cantidad\": 1}]'::jsonb, NULL);")
    lab.comprobar('La tablet no puede registrar pedidos salteando la sincronización',
                  'permission denied' in directo.stdout)
    locales = []
    for t in (t1, t2):
        locales.append(f'--- {t.dispositivo}: cola_sync')
        for f in t.db.execute('SELECT substr(solicitud_uuid, 1, 8) AS solicitud, substr(id_local, 1, 8) AS borrador, '
                              'estado, intentos, id_pedido_servidor FROM cola_sync ORDER BY creada_en'):
            locales.append('  ' + ' | '.join(str(v) for v in tuple(f)))
        locales.append(f"--- {t.dispositivo}: snapshots descargados: "
                       f"{t.db.execute('SELECT count(*) FROM snapshot').fetchone()[0]}")
        # Volcado SQL legible de la base local (el .db binario no se versiona).
        lab.guardar(f'u8_tablets/{t.dispositivo}.sql', '\n'.join(t.db.iterdump()) + '\n')
        t.cerrar()
    lab.guardar('u8_01_casos_sincronizacion.txt', '\n'.join(casos) + '\n')
    lab.guardar('u8_02_estado_tablets.txt', '\n'.join(locales) + '\n')
    lab.guardar('u8_03_estado_servidor.txt', servidor)


PASOS = {'base': paso_base, 'u4': paso_u4, 'u5': paso_u5, 'u6': paso_u6, 'u7': paso_u7,
         'u8': paso_u8}


def main() -> int:
    p = argumentos(__doc__.splitlines()[0])
    p.add_argument('--base', help='Reutilizar una base ya creada por este script (solo desarrollo)')
    p.add_argument('--pasos', default=','.join(PASOS), help='Lista separada por comas: ' + ', '.join(PASOS))
    args = p.parse_args()
    marca = sello()
    lab = Lab(args, args.base or f'food_store_tpi2_{marca}', TPI2 / 'evidencias' / marca)
    print(f'Base: {lab.base}\nEvidencias: {lab.carpeta}')
    if args.base:      # las claves viven en memoria: se vuelven a fijar para esta corrida
        lab.sql("BEGIN; SET LOCAL log_statement = 'none';\n" + '\n'.join(
            f"ALTER ROLE {rol} PASSWORD :'{var}';" for rol, var in ROLES_LOGIN.items()) + '\nCOMMIT;',
            variables=variables_claves(lab))
    exito, error = False, None
    try:
        for nombre in args.pasos.split(','):
            PASOS[nombre.strip()](lab)
        exito = True
    except (FalloEsperado, RuntimeError) as e:
        error = str(e)
        print(f'\nERROR: {error}', file=sys.stderr)
    resumen = {
        'base': lab.base, 'motor': lab.valor('SHOW server_version', base='postgres'), 'exito': exito,
        'error': error, 'duracion_segundos': round(time.perf_counter() - lab.inicio, 1),
        'total_comprobaciones': len(lab.comprobaciones),
        'comprobaciones': lab.comprobaciones,
    }
    lab.guardar('resultado.json', json.dumps(resumen, ensure_ascii=False, indent=2) + '\n')
    print(f"\n{'SEGUNDA ENTREGA VERIFICADA' if exito else 'FALLÓ'}: "
          f"{len(lab.comprobaciones)} comprobaciones en {resumen['duracion_segundos']} s")
    return 0 if exito else 1


if __name__ == '__main__':
    sys.exit(main())
