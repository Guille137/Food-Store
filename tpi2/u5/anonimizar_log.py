"""Unidad 5 · Anonimiza un fragmento de log antes de compartirlo con un asistente de IA.

Reemplaza, de forma consistente dentro del mismo texto:
  * correos            -> persona_N@anon.invalid
  * teléfonos          -> +00 0 00 0000-000N
  * direcciones IP     -> 203.0.113.N   (rango reservado para documentación)
  * nombres y apellidos que figuren en la lista recibida -> NOMBRE_N
  * hashes bcrypt/SCRAM -> [HASH]
  * rutas de archivos locales -> [RUTA]/archivo  (contienen el usuario del sistema operativo)
Conserva lo que hace falta para reconstruir un incidente: horas, roles de base de
datos, sentencias, códigos de error y qué registros son de la misma persona.

Uso:  python anonimizar_log.py entrada.txt salida.txt [--nombres archivo_con_un_nombre_por_linea]
También se usa como módulo: anonimizar(texto, nombres) -> (texto, resumen).
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

RE_CORREO = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
RE_TELEFONO = re.compile(r'\+\d{2} \d \d{2,3} \d{4}-\d{4}')
RE_IP = re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')
RE_RUTA = re.compile(r'''(?:[A-Za-z]:[\\/]|/(?:home|Users)/)[^\s"')]+''')
RE_HASH = re.compile(r'\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}|SCRAM-SHA-256\$[^\s\'"]+')


def anonimizar(texto: str, nombres: list[str] | None = None) -> tuple[str, dict]:
    mapas: dict[str, dict[str, str]] = {'correo': {}, 'telefono': {}, 'ip': {}, 'nombre': {}}

    def reemplazo(clase: str, formato: str):
        def f(m: re.Match) -> str:
            clave = m.group(0).lower()
            tabla = mapas[clase]
            if clave not in tabla:
                tabla[clave] = formato.format(len(tabla) + 1)
            return tabla[clave]
        return f

    texto = RE_HASH.sub('[HASH]', texto)
    # Las rutas locales delatan el nombre de la cuenta del sistema operativo.
    texto = RE_RUTA.sub(lambda m: '[RUTA]/' + re.split(r'[\\/]', m.group(0))[-1], texto)
    texto = RE_CORREO.sub(reemplazo('correo', 'persona_{}@anon.invalid'), texto)
    texto = RE_TELEFONO.sub(reemplazo('telefono', '+00 0 00 0000-{:04d}'), texto)
    texto = RE_IP.sub(reemplazo('ip', '203.0.113.{}'), texto)
    for nombre in sorted(set(nombres or []), key=len, reverse=True):
        if len(nombre) >= 3:
            patron = re.compile(r'(?<![A-Za-z_@.])' + re.escape(nombre) + r'(?![A-Za-z_@.])')
            texto = patron.sub(reemplazo('nombre', 'NOMBRE_{}'), texto)
    resumen = {clase: len(tabla) for clase, tabla in mapas.items()}
    return texto, resumen


def restos(texto: str) -> list[str]:
    """Datos identificables que hayan sobrevivido (debe devolver una lista vacía)."""
    hallados = [m for m in RE_CORREO.findall(texto) if not m.endswith('@anon.invalid')]
    hallados += [m for m in RE_TELEFONO.findall(texto) if not m.startswith('+00 0 00 0000-')]
    hallados += [m for m in RE_IP.findall(texto) if not m.startswith('203.0.113.')]
    hallados += RE_HASH.findall(texto)
    hallados += [m.group(0) for m in RE_RUTA.finditer(texto)]
    return hallados


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument('entrada', type=Path)
    p.add_argument('salida', type=Path)
    p.add_argument('--nombres', type=Path)
    a = p.parse_args()
    lista = a.nombres.read_text(encoding='utf-8').split('\n') if a.nombres else []
    resultado, cuenta = anonimizar(a.entrada.read_text(encoding='utf-8'), [n.strip() for n in lista if n.strip()])
    sobrantes = restos(resultado)
    if sobrantes:
        raise SystemExit(f'Quedaron datos identificables sin anonimizar: {sobrantes[:5]}')
    a.salida.write_text(resultado, encoding='utf-8', newline='\n')
    print('Anonimizado:', cuenta)
