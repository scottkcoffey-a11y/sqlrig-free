# Production Safety Rules (one-pager)

Agents and humans applying scripts from this toolkit must follow these rules.

1. **Default to dry-run.** Every write script ships with `@DryRun = 1` or `-WhatIf`. Flip it only after you have read the printed plan.
2. **No silent deletes.** Never `DROP`/`TRUNCATE`/`DELETE` without a `WHERE` (and a row-count estimate). Prefer batched deletes (`proc-batch-loop-safe.sql`).
3. **Backup note before data loss.** Before `DROP`/`TRUNCATE`/column drop/type narrowing, state: what was backed up, where, and how to restore.
4. **Ask before dangerous config.** Enabling `xp_cmdshell`, `Ole Automation`, CLR, changing `max server memory`, disabling constraints/triggers, or `KILL` requires an explicit human "yes" in the conversation.
5. **Transactions + XACT_ABORT.** Writes use `SET XACT_ABORT ON`, TRY/CATCH, and roll back on error. Prefer short transactions for batches.
6. **Idempotent by default.** Re-running a create script must not fail or duplicate. Prefer `IF NOT EXISTS` / `CREATE OR ALTER`. Never silently overwrite an existing Agent job, linked server, or alert.
7. **Least privilege.** Grant `EXECUTE` on procs / schemas to roles — not `db_owner` to application logins. Prefer Agent proxies over `xp_cmdshell`.
8. **No SSIS.** Schedule with SQL Server Agent; move data with T-SQL, linked servers, or PowerShell.
9. **Secrets stay out of scripts.** No passwords in `.sql`/`.ps1`. Use Windows/Entra auth, `Get-Credential`, or a secret store.
10. **Human gate.** Run `REVIEW-CHECKLIST.md` before applying agent-generated T-SQL in production.
