# Human Review Checklist — before applying agent-generated T-SQL in prod

Print this and tick it. If any item is "no", do not apply.

## Identity & target
- [ ] Script header states purpose, `COMPAT` version, and required permissions.
- [ ] Target server / database is the intended one (not a prod look-alike name by accident).
- [ ] Dry-run (`@DryRun = 1` / `-WhatIf`) was executed and the printed plan matches intent.
- [ ] Dry-run flags fail closed on NULL (`ISNULL(@DryRun, 1) = 1` or NULL rejected); `@DryRun = NULL` was tested and did not write.

## Correctness
- [ ] Every `UPDATE`/`DELETE` has a selective `WHERE`; estimated row count reviewed.
- [ ] Large DML is batched; transaction scope is short.
- [ ] Dynamic SQL uses `sp_executesql` parameters and `QUOTENAME` for identifiers.
- [ ] No `SELECT *` in procs that are part of an interface contract.

## Safety
- [ ] No `DROP`/`TRUNCATE`/`KILL`/config change unless explicitly requested and backed up.
- [ ] Rollback steps are written (and tested in a lower environment when risk is high).
- [ ] Existing objects are not silently overwritten (jobs, linked servers, alerts, users).
- [ ] No secrets in the script or in source control.

## Permissions & runtime
- [ ] Runs under least privilege (not personal sysadmin login for scheduled work).
- [ ] Agent jobs that shell out use a proxy, not `xp_cmdshell`.
- [ ] Failure notification / logging is defined for scheduled jobs.

## Sign-off
- [ ] Second pair of eyes (or change ticket) for High-risk changes.
- [ ] Reviewer: ______________  Date: ______________  Ticket: ______________
