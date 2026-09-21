Protocolo de seguridad - Food Store
Base de trabajo: PostgreSQL local. La base de desarrollo propuesta es food_store_tp2; no se trabaja sobre una base con datos reales.

1. Copia
Antes de cada práctica o cambio se crea una copia desde la base plantilla ya inicializada:

createdb -U postgres -T food_store_base food_store_tp2
Si food_store_tp2 ya existe, no se la reutiliza para un experimento nuevo: se crea otra copia con un nombre nuevo, por ejemplo food_store_tp2_20260917.

2. Transacción
Todo cambio se inspecciona primero dentro de una transacción. Los primeros ensayos terminan en ROLLBACK; solamente se usa COMMIT después de revisar los resultados.

BEGIN;
-- aplicar el script o el cambio
-- ejecutar pruebas de INSERT, UPDATE o DELETE
ROLLBACK;
Para instalar una migración ya probada se vuelve a abrir una transacción, se repiten las pruebas y recién entonces se ejecuta COMMIT.

3. Respaldo
Antes de cualquier DDL (ALTER, CREATE, DROP o migración) se guarda un respaldo independiente de la copia de trabajo:

New-Item -ItemType Directory -Force .\backups | Out-Null
pg_dump -U postgres -Fc -f .\backups\food_store_tp2_pre_ddl.dump food_store_tp2
Para recuperar ese respaldo en una base nueva:

createdb -U postgres food_store_tp2_restaurada
pg_restore -U postgres -d food_store_tp2_restaurada .\backups\food_store_tp2_pre_ddl.dump
Verificación previa
Antes de ejecutar, confirmo el destino con SELECT current_database(), current_user;, leo el diff completo y verifico que estoy conectado a la copia de trabajo.