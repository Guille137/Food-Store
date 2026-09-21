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
  - Cannot revert to `PENDIENTE` or modify after reaching `ENTREGADO` or `CANCELADO`.
- **Order Details (`detalle_pedido`):**
  - Can only INSERT, UPDATE, or DELETE line items while parent order is `PENDIENTE`.
  - Products must have `activo = TRUE` and requested `cantidad <= stock`.
