# AGENTS.md

## Database Setup & Workflows

- **Target Database:** Local PostgreSQL. Development database is `food_store_tp2` cloned from template `food_store_base`:
  `createdb -U postgres -T food_store_base food_store_tp2`
  - Do NOT overwrite an existing test DB; create timestamped copies (e.g., `food_store_tp2_20260917`).
- **Connection Safety:** Verify connected database before running any script:
  `SELECT current_database(), current_user;`
- **Backups before DDL:** Save a dump prior to any DDL or migration:
  `New-Item -ItemType Directory -Force .\backups | Out-Null`
  `pg_dump -U postgres -Fc -f .\backups\food_store_tp2_pre_ddl.dump food_store_tp2`
  - Restore: `createdb -U postgres <dbname>` then `pg_restore -U postgres -d <dbname> <dumpfile>`

## Safety & Testing Execution Protocol

- **Transactional Inspections:** Always test scripts inside an uncommitted transaction first:
  `BEGIN; -- execute script & tests; ROLLBACK;`
  Only `COMMIT;` after verifying output.
- **Handling Failure Tests:** Use `SAVEPOINT <name>` and `ROLLBACK TO SAVEPOINT <name>` in PostgreSQL test scripts (e.g., `pruebas_restricciones.sql`) when testing statements expected to raise errors (code `23514`) to prevent aborting the outer transaction block.
- **Verification Requirement:** Do not claim tests pass or commit without observing actual PostgreSQL output (`UPDATE`, `ERROR:`, `SELECT`). Record actual execution results in `DUIA parte 1.md`.

## Key Schema & Business Logic Constraints

- **Order State Transitions (`pedido`):**
  - Enum states: `PENDIENTE`, `CONFIRMADO`, `ENTREGADO`, `CANCELADO`.
  - Allowed transitions: `PENDIENTE` -> `CONFIRMADO` | `CANCELADO`; `CONFIRMADO` -> `ENTREGADO` | `CANCELADO`.
  - Cannot revert to `PENDIENTE` or change state after reaching `ENTREGADO` or `CANCELADO`; updating to the same state is allowed.
- **Order Details (`detalle_pedido`):**
  - Can only INSERT, UPDATE, or DELETE line items while parent order is `PENDIENTE`.
  - Products must have `activo = TRUE` and requested `cantidad <= stock`.
  - Moving a line requires both old and new orders to be PENDIENTE. Lock their rows with FOR SHARE in ascending id order; FOR KEY SHARE does not prevent concurrent updates to estado.
  - The stock check is per line; it does not reserve or decrement stock.

## Reproducible TP2 checks

- The current automated workflow is `verificar_tp2.py`; follow README.md and protocolo_seguridad.md for the actual environment and commands. It creates fresh timestamped databases from synthetic data instead of assuming the older fixed template exists.
- Install dependencies from requirements.txt. The PostgreSQL binaries, running server and credentials are provided separately; never commit credentials or database dumps.
- Keep the SQL test scripts inside an outer transaction. Their PL/pgSQL exception blocks are subtransactions and roll back expected failing statements, serving the same purpose as SAVEPOINT in interactive psql tests.
- Record actual output in evidencias/, summarize it in evidencia_ejecucion_tp2.md and reference it in duia_parte1.md. The legacy file `DUIA parte 1.md` points to that canonical declaration.
- The student confirmed freedom to choose the AI tool. Record Codex truthfully; do not claim OpenCode/Kiro or a model snapshot was used without evidence.
