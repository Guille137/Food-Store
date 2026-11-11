"""Utilidades comunes de la segunda entrega: ejecutar psql/mongosh y guardar evidencia.

No guarda contraseñas. La del superusuario de laboratorio se resuelve con el
archivo de contraseñas de PostgreSQL (PGPASSFILE / pgpass.conf) o PGPASSWORD;
las de los roles del proyecto se generan en cada corrida y viven solo en memoria.
Solo usa la biblioteca estándar de Python.
"""
from __future__ import annotations

import argparse
import os
import re
import secrets
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

TPI2 = Path(__file__).resolve().parent
REPO = TPI2.parent

ROLES_LOGIN = {
    'app_web': 'clave_app_web', 'admin_datos': 'clave_admin_datos', 'soporte_01': 'clave_soporte',
    'analista_01': 'clave_analista', 'auditor_01': 'clave_auditor',
    'operador_respaldo': 'clave_respaldo', 'tablet_feria': 'clave_tablet',
}


def argumentos(descripcion: str) -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=descripcion)
    p.add_argument('--pg-bin', type=Path, default=os.environ.get('FS_PGBIN'),
                   help='Carpeta bin de PostgreSQL 16+ (o variable FS_PGBIN)')
    p.add_argument('--host', default=os.environ.get('PGHOST', '127.0.0.1'))
    p.add_argument('--port', default=os.environ.get('PGPORT', '5432'))
    p.add_argument('--user', default=os.environ.get('PGUSER', 'postgres'),
                   help='Superusuario del servidor de laboratorio')
    p.add_argument('--mongosh', default=os.environ.get('FS_MONGOSH', 'mongosh'))
    p.add_argument('--mongo-uri', default=os.environ.get('FS_MONGO_URI', 'mongodb://127.0.0.1:27017'))
    return p


class FalloEsperado(Exception):
    """Una comprobación del laboratorio no dio el resultado previsto."""


class Lab:
    def __init__(self, args, base: str, carpeta: Path):
        if not args.pg_bin:
            sys.exit('Falta --pg-bin (o la variable FS_PGBIN) con la carpeta bin de PostgreSQL')
        self.pg_bin = Path(args.pg_bin)
        self.host, self.port, self.user = args.host, str(args.port), args.user
        self.mongosh, self.mongo_uri = args.mongosh, args.mongo_uri
        self.base = base
        self.carpeta = carpeta
        carpeta.mkdir(parents=True, exist_ok=True)
        self.claves = {rol: secrets.token_urlsafe(18) for rol in ROLES_LOGIN}
        self.comprobaciones: list[dict] = []
        self.inicio = time.perf_counter()

    # ------------------------------------------------------------------ procesos
    def exe(self, nombre: str) -> str:
        return str(self.pg_bin / (nombre + ('.exe' if os.name == 'nt' else '')))

    def entorno(self, rol: str | None = None, clave: str | None = None, app: str | None = None) -> dict:
        env = dict(os.environ, PGCLIENTENCODING='UTF8', PGHOST=self.host, PGPORT=self.port,
                   PGCONNECT_TIMEOUT='10')
        env['PGUSER'] = rol or self.user
        if rol:                      # rol del proyecto: nunca usa la clave del superusuario
            env.pop('PGPASSFILE', None)
            env['PGPASSWORD'] = clave if clave is not None else self.claves[rol]
        if app:
            env['PGAPPNAME'] = app
        return env

    def psql(self, *args: str, base: str | None = None, rol: str | None = None,
             clave: str | None = None, app: str | None = None, entrada: str | None = None,
             variables: dict | None = None, tolerar_error: bool = False) -> subprocess.CompletedProcess:
        """Ejecuta psql desde la raíz del repositorio. Devuelve stdout+stderr juntos."""
        cmd = [self.exe('psql'), '-X', '-d', base or self.base]
        if not tolerar_error:
            cmd += ['-v', 'ON_ERROR_STOP=1']
        for k, v in (variables or {}).items():
            cmd += ['-v', f'{k}={v}']
        cmd += list(args)
        r = subprocess.run(cmd, cwd=REPO, env=self.entorno(rol, clave, app), input=entrada,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, encoding='utf-8', errors='replace')
        if r.returncode != 0 and not tolerar_error:
            raise RuntimeError(f'psql terminó con código {r.returncode}:\n{r.stdout[-3000:]}')
        return r

    def sql(self, texto: str, **kw) -> str:
        """Ejecuta SQL recibido por la entrada estándar (admite variables :'x')."""
        return self.psql('-f', '-', entrada=texto, **kw).stdout

    def valor(self, texto: str, **kw) -> str:
        return self.psql('-At', '-f', '-', entrada=texto, **kw).stdout.strip()

    def herramienta(self, nombre: str, *args: str, rol: str | None = None,
                    tolerar_error: bool = False) -> subprocess.CompletedProcess:
        r = subprocess.run([self.exe(nombre), *args], cwd=REPO, env=self.entorno(rol),
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, encoding='utf-8', errors='replace')
        if r.returncode != 0 and not tolerar_error:
            raise RuntimeError(f'{nombre} terminó con código {r.returncode}:\n{r.stdout[-3000:]}')
        return r

    def mongo(self, *args: str, tolerar_error: bool = False) -> subprocess.CompletedProcess:
        r = subprocess.run([self.mongosh, self.mongo_uri, '--quiet', *args], cwd=REPO,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, encoding='utf-8', errors='replace')
        if r.returncode != 0 and not tolerar_error:
            raise RuntimeError(f'mongosh terminó con código {r.returncode}:\n{r.stdout[-3000:]}')
        return r

    def huella(self, base: str | None = None) -> str:
        """Contenido completo de la base resumido en líneas tabla|filas|md5."""
        return self.psql('-At', '-f', 'tpi2/base/huella.sql', base=base).stdout.strip()

    # ----------------------------------------------------------------- evidencia
    def guardar(self, nombre: str, contenido: str) -> Path:
        # Las rutas locales delatan la cuenta del sistema operativo: se reemplazan.
        for ruta, marca in ((REPO, '<repo>'), (Path.home(), '<home>')):
            for variante in {str(ruta).replace('\\', '\\\\'), str(ruta), ruta.as_posix()}:  # incluye JSON
                contenido = contenido.replace(variante, marca)
        contenido = re.sub(r'[A-Za-z]:(?:\\\\|\\|/)Users(?:\\\\|\\|/)[^\\/\s"\')]+', '<home>', contenido, flags=re.I)
        destino = self.carpeta / nombre
        destino.parent.mkdir(parents=True, exist_ok=True)
        destino.write_text(contenido, encoding='utf-8', newline='\n')
        return destino

    def comprobar(self, nombre: str, condicion: bool, detalle: str = '') -> None:
        self.comprobaciones.append({'comprobacion': nombre, 'correcta': bool(condicion), 'detalle': detalle})
        print(('  OK   ' if condicion else '  FALLA ') + nombre + (f' — {detalle}' if detalle else ''), flush=True)
        if not condicion:
            raise FalloEsperado(f'{nombre}: {detalle}')

    def titulo(self, texto: str) -> None:
        print(f'\n=== {texto} ===', flush=True)

    # ------------------------------------------------------------- log servidor
    def ruta_log(self) -> Path:
        ruta = self.valor("SELECT current_setting('data_directory') || '/' || pg_current_logfile()")
        return Path(ruta)

    def marca_log(self) -> tuple[Path, int]:
        ruta = self.ruta_log()
        return ruta, ruta.stat().st_size

    def log_desde(self, marca: tuple[Path, int]) -> str:
        time.sleep(1.0)              # el recolector de logs escribe con un pequeño retraso
        ruta, desde = marca
        with open(ruta, 'rb') as f:
            f.seek(desde)
            return f.read().decode('utf-8', errors='replace')


def sello() -> str:
    return datetime.now().strftime('%Y%m%d_%H%M%S')
