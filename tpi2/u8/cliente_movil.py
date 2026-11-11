"""Unidad 8 · Cliente de la tablet de feria: base SQLite local + sincronización con PostgreSQL.

Política de sincronización (design.md de la spec U8):
  * Bajada: el servidor es la fuente de verdad del catálogo. La tablet reemplaza
    su copia con cada instantánea; lo que ya no viene queda como lápida.
  * Subida: la tablet PROPONE pedidos; el servidor DISPONE (sync.aplicar_solicitud).
    Cada solicitud lleva un UUID: reenviarla no duplica la venta.
  * Conflictos:
      RECHAZADO  (producto inexistente o dado de baja, categoría inactiva, sin stock):
                 definitivo; la persona arma otro borrador.
      CONFLICTO  (cambió el precio): gana el servidor. La persona acepta el precio
                 nuevo y el borrador se reenvía con OTRO UUID (es otra propuesta).
  * Sin conexión: la solicitud queda PENDIENTE y se reintenta; nada se pierde.

El acceso al servidor se inyecta como una función `ejecutar_sql(texto) -> str`
(en el laboratorio, psql con el rol tablet_feria). Si no hay conexión debe lanzar
SinConexion. Solo usa la biblioteca estándar de Python.
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

ESQUEMA = Path(__file__).resolve().parent / 'movil_schema.sql'

CONSULTA_SNAPSHOT = """
SELECT json_build_object(
    'servidor_en', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'productos', json_agg(json_build_object(
        'id', id, 'nombre', nombre, 'categoria', categoria, 'precio_centavos', precio_centavos,
        'stock', stock, 'disponible', disponible, 'eliminado', eliminado) ORDER BY id))
FROM sync.v_snapshot_movil;
"""


class SinConexion(Exception):
    """El servidor no está disponible."""


class SnapshotInvalido(Exception):
    """La instantánea recibida no puede reemplazar el catálogo local."""


def ahora() -> str:
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ')


class Tablet:
    def __init__(self, ruta: Path, dispositivo: str, ejecutar_sql: Callable[[str], str]):
        self.dispositivo = dispositivo
        self.ejecutar_sql = ejecutar_sql
        nueva = not Path(ruta).exists()
        # isolation_level=None: las transacciones se manejan explícitamente (BEGIN/COMMIT).
        # check_same_thread=False: la prueba de concurrencia envía desde otro hilo;
        # cada tablet usa su conexión desde un único hilo a la vez.
        self.db = sqlite3.connect(ruta, isolation_level=None, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys = ON')
        if nueva:
            self.db.executescript(ESQUEMA.read_text(encoding='utf-8'))

    # ------------------------------------------------------------------ catálogo
    def descargar_catalogo(self) -> int:
        """Baja la instantánea y la aplica en UNA transacción. Devuelve la versión."""
        datos = json.loads(self.ejecutar_sql(CONSULTA_SNAPSHOT))
        return self.aplicar_snapshot(datos)

    def aplicar_snapshot(self, datos: dict) -> int:
        productos = datos.get('productos') or []
        if not productos:
            raise SnapshotInvalido('Instantánea vacía: se conserva el catálogo anterior')
        c = self.db
        c.execute('BEGIN IMMEDIATE')
        try:
            version = c.execute('INSERT INTO snapshot (servidor_en, descargado_en, productos) VALUES (?, ?, ?)',
                                (datos['servidor_en'], ahora(), len(productos))).lastrowid
            for p in productos:
                c.execute("""
                    INSERT INTO producto_cache (id, nombre, categoria, precio_centavos, stock_visto,
                                                disponible, eliminado, version_snapshot)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (id) DO UPDATE SET nombre = excluded.nombre, categoria = excluded.categoria,
                        precio_centavos = excluded.precio_centavos, stock_visto = excluded.stock_visto,
                        disponible = excluded.disponible, eliminado = excluded.eliminado,
                        version_snapshot = excluded.version_snapshot""",
                          (p['id'], p['nombre'], p['categoria'], p['precio_centavos'], p['stock'],
                           int(p['disponible']), int(p['eliminado']), version))
            # Lo que el servidor ya no publica queda como lápida.
            c.execute('UPDATE producto_cache SET disponible = 0, eliminado = 1, version_snapshot = ? '
                      'WHERE version_snapshot <> ?', (version, version))
            c.execute('COMMIT')
            return version
        except Exception:
            c.execute('ROLLBACK')
            raise

    def catalogo(self) -> list[dict]:
        return [dict(r) for r in self.db.execute('SELECT * FROM v_catalogo')]

    # ------------------------------------------------------------------ borradores
    def crear_borrador(self, forma_pago: str, items: list[tuple[int, int]]) -> str:
        """items: [(producto_id, cantidad)]. El precio visto es el de la copia local."""
        id_local = str(uuid.uuid4())
        c = self.db
        c.execute('BEGIN IMMEDIATE')
        try:
            c.execute('INSERT INTO pedido_borrador (id_local, forma_pago, creado_en) VALUES (?, ?, ?)',
                      (id_local, forma_pago, ahora()))
            for producto_id, cantidad in items:
                fila = c.execute('SELECT precio_centavos FROM producto_cache WHERE id = ? '
                                 'AND disponible = 1 AND eliminado = 0', (producto_id,)).fetchone()
                if fila is None:
                    raise ValueError(f'El producto {producto_id} no está en el catálogo disponible')
                c.execute('INSERT INTO item_borrador VALUES (?, ?, ?, ?)',
                          (id_local, producto_id, cantidad, fila['precio_centavos']))
            c.execute('COMMIT')
            return id_local
        except Exception:
            c.execute('ROLLBACK')
            raise

    def encolar(self, id_local: str) -> str:
        solicitud = str(uuid.uuid4())
        c = self.db
        c.execute('BEGIN IMMEDIATE')
        try:
            c.execute('INSERT INTO cola_sync (solicitud_uuid, id_local, creada_en) VALUES (?, ?, ?)',
                      (solicitud, id_local, ahora()))
            c.execute("UPDATE pedido_borrador SET estado = 'ENVIADO' WHERE id_local = ?", (id_local,))
            c.execute('COMMIT')
            return solicitud
        except Exception:
            c.execute('ROLLBACK')
            raise

    def solicitud_json(self, solicitud: str) -> dict:
        fila = self.db.execute('SELECT q.solicitud_uuid, b.id_local, b.forma_pago FROM cola_sync q '
                               'JOIN pedido_borrador b USING (id_local) WHERE q.solicitud_uuid = ?',
                               (solicitud,)).fetchone()
        items = [{'producto_id': r['producto_id'], 'cantidad': r['cantidad'],
                  'precio_centavos_visto': r['precio_centavos_visto']}
                 for r in self.db.execute('SELECT * FROM item_borrador WHERE id_local = ? ORDER BY producto_id',
                                          (fila['id_local'],))]
        return {'solicitud_uuid': fila['solicitud_uuid'], 'dispositivo': self.dispositivo,
                'forma_pago': fila['forma_pago'], 'items': items}

    # ------------------------------------------------------------------ subida
    def enviar(self, solicitud: str, perder_respuesta: bool = False) -> dict | None:
        """Envía UNA solicitud pendiente. perder_respuesta simula que la red se corta
        después de que el servidor confirmó pero antes de que llegue la respuesta."""
        cuerpo = json.dumps(self.solicitud_json(solicitud), separators=(',', ':'))
        marca = '$sync_' + uuid.uuid4().hex[:8] + '$'
        self.db.execute('UPDATE cola_sync SET intentos = intentos + 1, ultimo_intento = ? WHERE solicitud_uuid = ?',
                        (ahora(), solicitud))
        try:
            texto = self.ejecutar_sql(f'SELECT sync.aplicar_solicitud({marca}{cuerpo}{marca}::jsonb);')
        except SinConexion as e:
            self.db.execute('UPDATE cola_sync SET ultimo_error = ? WHERE solicitud_uuid = ?',
                            (str(e)[:200], solicitud))
            return None
        if perder_respuesta:
            return None
        respuesta = json.loads(texto)
        self.registrar_respuesta(solicitud, respuesta)
        return respuesta

    def registrar_respuesta(self, solicitud: str, r: dict) -> None:
        estado = r['estado']
        c = self.db
        c.execute('BEGIN IMMEDIATE')
        try:
            c.execute('UPDATE cola_sync SET estado = ?, respuesta = ?, id_pedido_servidor = ?, ultimo_error = NULL '
                      'WHERE solicitud_uuid = ?', (estado, json.dumps(r), r.get('id_pedido'), solicitud))
            c.execute('UPDATE pedido_borrador SET estado = ?, id_pedido_servidor = ? '
                      'WHERE id_local = (SELECT id_local FROM cola_sync WHERE solicitud_uuid = ?)',
                      ('CONFIRMADO' if estado == 'APLICADO' else estado, r.get('id_pedido'), solicitud))
            c.execute('COMMIT')
        except Exception:
            c.execute('ROLLBACK')
            raise

    def sincronizar(self) -> dict:
        """Envía todas las pendientes en orden de creación. Si se corta la conexión, se detiene."""
        resultado = {'enviadas': 0, 'sin_conexion': False}
        for fila in self.db.execute("SELECT solicitud_uuid FROM cola_sync WHERE estado = 'PENDIENTE' "
                                    'ORDER BY creada_en').fetchall():
            if self.enviar(fila['solicitud_uuid']) is None:
                resultado['sin_conexion'] = True
                break
            resultado['enviadas'] += 1
        return resultado

    def aceptar_precios_y_reenviar(self, id_local: str) -> str:
        """Resolución de CONFLICTO: gana el servidor. Toma los precios de la copia
        local (ya actualizada) y crea una solicitud nueva con otro UUID."""
        c = self.db
        c.execute('BEGIN IMMEDIATE')
        try:
            estado = c.execute('SELECT estado FROM pedido_borrador WHERE id_local = ?', (id_local,)).fetchone()[0]
            if estado != 'CONFLICTO':
                raise ValueError('Solo se reenvía un borrador en CONFLICTO')
            c.execute('UPDATE item_borrador SET precio_centavos_visto = '
                      '(SELECT precio_centavos FROM producto_cache p WHERE p.id = item_borrador.producto_id) '
                      'WHERE id_local = ?', (id_local,))
            c.execute("UPDATE pedido_borrador SET estado = 'BORRADOR' WHERE id_local = ?", (id_local,))
            c.execute('COMMIT')
        except Exception:
            c.execute('ROLLBACK')
            raise
        return self.encolar(id_local)

    # ------------------------------------------------------------------ control
    def estado(self, solicitud: str) -> sqlite3.Row:
        return self.db.execute('SELECT * FROM cola_sync WHERE solicitud_uuid = ?', (solicitud,)).fetchone()

    def integridad(self) -> tuple[str, list]:
        return (self.db.execute('PRAGMA integrity_check').fetchone()[0],
                [tuple(r) for r in self.db.execute('PRAGMA foreign_key_check')])

    def cerrar(self) -> None:
        self.db.close()
