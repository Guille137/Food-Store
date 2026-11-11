# Requisitos — Migración de la planilla heredada a BCNF (Unidad 4)

## Introducción

Food Store conserva la planilla de ventas 2025 del sistema anterior (`legado.venta_planilla`): una sola tabla sin clave, que repite en cada renglón los datos del cliente, del producto, del rubro y del repartidor. Hay que incorporar esas ventas al modelo normalizado sin perder ni inventar datos, de forma reversible y verificable.

## Requisito 1 — Dependencias validadas contra los datos

**Historia:** Como responsable de datos, quiero comprobar cada dependencia funcional sobre los datos reales antes de diseñar las tablas, para no normalizar sobre supuestos falsos.

**Criterios de aceptación**

1. CUANDO se ejecute `02_verificar_dependencias.sql`, EL SISTEMA DEBERÁ informar, para cada dependencia candidata, cuántos valores del determinante la violan sobre los datos crudos y sobre la forma canónica.
2. CUANDO una dependencia tenga violaciones en la forma canónica, EL SISTEMA DEBERÁ listar los valores que la violan.
3. EL SISTEMA DEBERÁ ser de solo lectura durante la validación.

## Requisito 2 — Esquema en forma normal de Boyce-Codd

1. EL SISTEMA DEBERÁ representar cada dependencia funcional validada mediante la clave primaria o una clave única de una tabla, de modo que todo determinante sea superclave.
2. SI una dependencia no se cumple en los datos (por ejemplo `email -> telefono`), ENTONCES EL SISTEMA NO DEBERÁ usarla como clave y DEBERÁ documentar la regla aplicada.

## Requisito 3 — Migración sin pérdida dentro de una transacción reversible

1. EL SISTEMA DEBERÁ ejecutar toda la migración en una única transacción controlada por quien la invoca (el script no contiene `BEGIN` ni `COMMIT`).
2. CUANDO la migración termine, EL SISTEMA DEBERÁ verificar en la misma transacción que: renglones del legado = renglones migrados + renglones en cuarentena; el importe total coincide; la reconstrucción por reunión de las tablas nuevas es igual al legado canónico en ambos sentidos (`EXCEPT ALL`).
3. SI alguna verificación falla, ENTONCES EL SISTEMA DEBERÁ abortar y no dejar ningún cambio.
4. CUANDO un renglón no tenga los datos obligatorios, EL SISTEMA DEBERÁ guardarlo completo en `migracion.cuarentena` con el motivo, en lugar de descartarlo.
5. CUANDO un valor del legado contradiga a otro que se conserva, EL SISTEMA DEBERÁ registrarlo en `migracion.discrepancia`.
6. EL SISTEMA NO DEBERÁ modificar ni borrar la planilla heredada.

## Requisito 4 — Plan de reversión obligatorio

1. ANTES de migrar, EL SISTEMA DEBERÁ contar con un respaldo `pg_dump` de la base.
2. MIENTRAS la transacción no se haya confirmado, la reversión DEBERÁ ser `ROLLBACK` (nivel 1).
3. CUANDO la migración ya esté confirmada, `05_reversion.sql` DEBERÁ eliminar exactamente lo creado por la migración, guiándose por los mapas, y dejar la base con el mismo contenido que antes de migrar (nivel 2).
4. SI después de migrar se crearon datos nuevos que dependen de lo migrado, ENTONCES la reversión DEBERÁ detenerse sin cambiar nada.
5. SI la base quedara inutilizable, ENTONCES se restaurará el respaldo previo (nivel 3).

## Requisito 5 — Desnormalización controlada

1. EL SISTEMA DEBERÁ conservar la desnormalización de la Unidad 4 (materializada de ventas por día y categoría) sincronizada con la fuente normalizada después de la migración.
2. CUANDO se ejecute la auditoría `unidad4.auditoria_ventas`, EL SISTEMA DEBERÁ devolver cero filas.
