# Protocolo de seguridad — Food Store

## Entorno utilizado

La comprobación del 22/09/2026 se realizó en Windows con PostgreSQL 17.11, en una instancia local aislada en `127.0.0.1:55432`, usuario `postgres`. Los binarios y el clúster se encuentran fuera del repositorio, en `../revision_material/postgres_local/`. Solo se usaron datos sintéticos de `datos_iniciales.sql`.

`verificar_tp2.py` implementa este protocolo. Crea bases con nombres `food_store_tp2_<fecha UTC>_<sufijo>`; no reutiliza ni elimina bases existentes.

## 1. Copia

El ejecutor crea una base nueva con `schema.sql` y `datos_iniciales.sql`, después de ensayar ambos con ROLLBACK. Cierra sus conexiones y crea una copia mediante `CREATE DATABASE ... TEMPLATE ...`. Cada escenario tiene su propia copia.

Equivalente manual, reemplazando FECHA por un identificador nuevo:

```powershell
createdb -h 127.0.0.1 -p 55432 -U postgres -T food_store_tp2_FECHA_base food_store_tp2_FECHA_trabajo
```

La primera consulta de cada conexión es `SELECT current_database(), current_user, version()`. Los nombres concretos figuran en el registro de evidencia.

## 2. Transacción

Primero se inspecciona la migración y sus pruebas dentro de una transacción que se revierte:

```sql
BEGIN;
-- ejecutar restricciones_Food_Store.sql
-- ejecutar pruebas_restricciones.sql
ROLLBACK;
```

Solo después de pasar las pruebas se aplica la migración con COMMIT. Se repiten las pruebas con ROLLBACK y se comprueba que no quedaron detalles de prueba. Los errores esperados se capturan en subtransacciones PL/pgSQL: revierten la sentencia fallida y permiten continuar. En una sesión manual se pueden usar SAVEPOINT y ROLLBACK TO SAVEPOINT.

Los experimentos concurrentes requieren algunos COMMIT para mostrar cambios entre sesiones. Primero se ensaya la escritura con ROLLBACK; luego se reproduce sobre una copia exclusiva del escenario. La lectura crítica utiliza tablas temporales y se revierte completamente.

## 3. Respaldo

Antes del esquema inicial se respalda la base vacía y antes de la migración se respalda la copia con esquema y datos. El ejecutor usa pg_dump en formato custom y comprueba su código de salida:

```powershell
pg_dump -h 127.0.0.1 -p 55432 -U postgres -Fc -f .\backups\food_store_tp2_FECHA_trabajo_pre_ddl.dump food_store_tp2_FECHA_trabajo
```

Los dumps quedan en `backups/`, excluidos de Git. El archivo histórico `backups/schema.sql` no reemplaza estos respaldos completos.

Restauración prevista en otra base nueva (instrucciones documentadas, no ejecutadas en esta comprobación):

```powershell
createdb -h 127.0.0.1 -p 55432 -U postgres food_store_tp2_FECHA_restaurada
pg_restore -h 127.0.0.1 -p 55432 -U postgres -d food_store_tp2_FECHA_restaurada .\backups\food_store_tp2_FECHA_trabajo_pre_ddl.dump
```
