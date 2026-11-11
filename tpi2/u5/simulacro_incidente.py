"""Unidad 5 · Simulacro de acceso indebido (SOLO contra la base de laboratorio propia).

Reproduce, con datos sintéticos, la secuencia de un ataque:
  1. Varios intentos fallidos contra fn_autenticar y luego uno exitoso
     (la clave de una cuenta de soporte fue adivinada desde el formulario web).
  2. Intentos fallidos de conexión directa a PostgreSQL con el rol soporte_01 y
     luego uno exitoso (la persona reutilizaba la misma clave).
  3. Lectura masiva de usuario y de cliente con ese rol.
  4. Una modificación permitida a ese rol (teléfono de un cliente).
  5. Intentos de escalar privilegios hacia rol_admin_datos.

Cada paso declara el resultado ESPERADO según el diseño de permisos. Si un
intento de escalamiento NO falla, el simulacro termina con error: sería un
defecto de 04_roles.sql que hay que corregir antes de seguir.

Lo invoca tpi2/ejecutar_todo.py; no se ejecuta contra ningún otro servidor.
"""
from __future__ import annotations

import hashlib

VICTIMA = 'usuario3@foodstore.example'          # cuenta sintética con rol_aplicacion SOPORTE
APP_LEGITIMA = 'foodstore-web'
APP_ATACANTE = 'psql'
CLIENTE_MODIFICADO = 10
TELEFONO_FALSO = '+54 9 11 5555-9999'


def clave_laboratorio(n: int) -> str:
    """Misma derivación que 01_usuario_autenticacion.sql (no es un secreto real)."""
    return 'Lab-' + hashlib.md5(f'clave{n}'.encode()).hexdigest()[:10]


def ejecutar(lab) -> list[dict]:
    pasos: list[dict] = []

    def paso(etapa: str, accion: str, esperado: str, salida: str, ocurrio: bool) -> None:
        correcto = (esperado == 'PERMITIDO') == ocurrio
        pasos.append({'etapa': etapa, 'accion': accion, 'esperado': esperado,
                      'obtenido': 'PERMITIDO' if ocurrio else 'DENEGADO',
                      'salida': salida.strip().splitlines()[-1] if salida.strip() else ''})
        lab.comprobar(f'Simulacro · {accion}', correcto,
                      f"esperado {esperado}, obtenido {'PERMITIDO' if ocurrio else 'DENEGADO'}")

    # 1. Fuerza bruta sobre el formulario de ingreso (pasa por la aplicación web).
    for intento, clave in enumerate(['123456', 'foodstore', 'Soporte2026', 'qwerty'], start=1):
        r = lab.valor("SELECT public.fn_autenticar(:'correo', :'clave')", rol='app_web',
                      app=APP_LEGITIMA, variables={'correo': VICTIMA, 'clave': clave})
        paso('1-fuerza-bruta', f'fn_autenticar intento fallido {intento}', 'DENEGADO', r, r == 't')
    r = lab.valor("SELECT public.fn_autenticar(:'correo', :'clave')", rol='app_web',
                  app=APP_LEGITIMA, variables={'correo': VICTIMA, 'clave': clave_laboratorio(3)})
    paso('1-fuerza-bruta', 'fn_autenticar con la clave adivinada', 'PERMITIDO', r, r == 't')

    # 2. Conexión directa a la base con el rol personal de soporte.
    for intento in range(1, 4):
        r = lab.psql('-Atc', 'SELECT 1', rol='soporte_01', clave=f'clave-incorrecta-{intento}',
                     app=APP_ATACANTE, tolerar_error=True)
        paso('2-conexion', f'conexión soporte_01 con clave errónea {intento}', 'DENEGADO',
             r.stdout, r.returncode == 0)
    r = lab.psql('-Atc', 'SELECT current_user', rol='soporte_01', app=APP_ATACANTE, tolerar_error=True)
    paso('2-conexion', 'conexión soporte_01 con la clave reutilizada', 'PERMITIDO', r.stdout, r.returncode == 0)

    def como_soporte(etapa: str, accion: str, esperado: str, sql: str) -> str:
        r = lab.psql('-At', '-c', sql, rol='soporte_01', app=APP_ATACANTE, tolerar_error=True)
        paso(etapa, accion, esperado, r.stdout, r.returncode == 0 and 'ERROR' not in r.stdout)
        return r.stdout

    # 3. Lectura masiva.
    como_soporte('3-lectura', 'SELECT * FROM usuario (incluye el hash)', 'DENEGADO',
                 'SELECT * FROM public.usuario')
    salida = como_soporte('3-lectura', 'lectura masiva de usuario (columnas permitidas)', 'PERMITIDO',
                          'SELECT id_usuario, correo_electronico, nombre, apellido, rol_aplicacion '
                          'FROM public.usuario ORDER BY id_usuario')
    filas_usuario = len(salida.strip().splitlines())
    salida = como_soporte('3-lectura', 'lectura masiva de cliente (correo y teléfono)', 'PERMITIDO',
                          'SELECT id_cliente, correo_electronico, nro_telefono, nombre, apellido '
                          'FROM public.cliente ORDER BY id_cliente')
    filas_cliente = len(salida.strip().splitlines())

    # 4. Modificación que el rol sí tiene permitida.
    como_soporte('4-modificacion', 'cambio del teléfono de un cliente', 'PERMITIDO',
                 f"UPDATE public.cliente SET nro_telefono = '{TELEFONO_FALSO}' "
                 f"WHERE id_cliente = {CLIENTE_MODIFICADO}")

    # 5. Escalamiento de privilegios: todo esto debe fallar.
    como_soporte('5-escalamiento', 'GRANT rol_admin_datos TO soporte_01', 'DENEGADO',
                 'GRANT rol_admin_datos TO soporte_01')
    como_soporte('5-escalamiento', 'SET ROLE rol_admin_datos', 'DENEGADO', 'SET ROLE rol_admin_datos')
    como_soporte('5-escalamiento', 'restablecer la clave de un administrador', 'DENEGADO',
                 "SELECT public.fn_resetear_password('usuario5@foodstore.example')")
    como_soporte('5-escalamiento', 'UPDATE usuario SET rol_aplicacion = ADMIN', 'DENEGADO',
                 "UPDATE public.usuario SET rol_aplicacion = 'ADMIN' "
                 f"WHERE correo_electronico = '{VICTIMA}'")
    como_soporte('5-escalamiento', 'ALTER ROLE soporte_01 SUPERUSER', 'DENEGADO',
                 'ALTER ROLE soporte_01 SUPERUSER')
    como_soporte('5-escalamiento', 'borrar el rastro en auditoria.registro', 'DENEGADO',
                 'DELETE FROM auditoria.registro')
    como_soporte('5-escalamiento', 'CREATE TABLE en public', 'DENEGADO',
                 'CREATE TABLE public.botin AS SELECT 1 AS x')

    pasos.append({'etapa': 'resumen', 'accion': 'filas leídas', 'esperado': '', 'obtenido': '',
                  'salida': f'usuario: {filas_usuario} filas; cliente: {filas_cliente} filas'})
    return pasos
