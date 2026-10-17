# SQL Rig Free: AI agent starter kit for SQL Server

SQL Rig gives AI coding agents (Cursor, Claude Code, GitHub Copilot) a safe, tested set of T-SQL and PowerShell to work from when they touch SQL Server. This repo is the free 14-file pack. The full kit has 47 tested T-SQL and PowerShell files plus agent prompts and rules.

- Site: https://sqlrig.com
- Free pack page: https://sqlrig.com/free
- Full pack ($39 one-time, $79 with 12 months of updates): https://coffeyscott.gumroad.com/l/sql-server

## Safety defaults

- Write scripts default to `@DryRun = 1`. They print what they would do and change nothing until you set `@DryRun = 0`.
- PowerShell scripts support `-WhatIf`.
- Idempotent templates: if the object already exists, nothing is changed (no silent overwrite).
- Each T-SQL file has a header with purpose, compatibility, required permissions, usage, and rollback.
- Guardrails in `04-guardrails/` (review checklist and prod safety rules) are meant to be read by both the agent and the human before anything runs in production.
- No SSIS.

Scripts are provided as-is. Test in non-production first.

## Quick start (about 10 minutes)

1. Load the system prompt `01-prompts/agent-sql-dba-system.md` into your agent (see below).
2. Run `03-powershell/Invoke-SqlSmokeTest.ps1 -ServerInstance <server> -WhatIf`, then without `-WhatIf`.
3. Open `02-tsql/agent-job-create-template.sql`, leave `@DryRun = 1`, run it, and read the plan.
4. Before applying anything in production, go through `04-guardrails/REVIEW-CHECKLIST.md` and `04-guardrails/PROD-SAFETY.md`.

### Cursor

Copy `01-prompts/agent-sql-dba-system.md` into a project rule, for example `.cursor/rules/sql-dba.mdc`, or paste it into Cursor Settings > Rules. Keep this repo in the workspace so the agent can reference the scripts.

### Claude Code

Paste the contents of `01-prompts/agent-sql-dba-system.md` into `CLAUDE.md` at your project root, or reference it from there (for example: "Follow the rules in 01-prompts/agent-sql-dba-system.md and 04-guardrails/").

### GitHub Copilot

Paste the prompt into `.github/copilot-instructions.md` in your repo. Copilot Chat in VS Code picks it up as custom instructions.

## Files

| Path | What it does |
|---|---|
| `QUICKSTART.md` | 10-minute path |
| `01-prompts/agent-sql-dba-system.md` | System prompt for a SQL Server DBA agent |
| `02-tsql/agent-job-create-template.sql` | Create a SQL Agent job, category, and schedule. Idempotent, dry-run default |
| `02-tsql/blocking-chain.sql` | Current blocking chains and head blockers. Read-only |
| `02-tsql/expensive-queries.sql` | Top queries by CPU, duration, and logical reads. Read-only |
| `02-tsql/linked-server-test.sql` | Connectivity and latency test for one or all linked servers. Read-only |
| `02-tsql/orphaned-users-fix.sql` | Detect SQL users orphaned after a restore; optional remap |
| `02-tsql/proc-template-safe.sql` | Stored procedure template: NOCOUNT, XACT_ABORT, TRY/CATCH, validated parameters, @DryRun |
| `02-tsql/wait-stats-delta.sql` | Wait stats delta over N seconds. Read-only |
| `02-tsql/xp-cmdshell-check.sql` | Surface-area audit: xp_cmdshell, Ole Automation, CLR, Database Mail XPs, and more. Read-only |
| `03-powershell/Get-SqlBlockingSnapshot.ps1` | Capture the blocking chain to CSV and/or JSON for tickets |
| `03-powershell/Invoke-SqlSmokeTest.ps1` | Connection smoke test: @@VERSION and database ONLINE check |
| `04-guardrails/REVIEW-CHECKLIST.md` | Pre-change review checklist |
| `04-guardrails/PROD-SAFETY.md` | Production safety rules for agents |

## The full pack

The paid pack adds multi-step Agent jobs, linked-server add and OPENQUERY scripts, the full PowerShell suite, Cursor and Copilot rules, and the update stream (47 files total). Get it at https://coffeyscott.gumroad.com/l/sql-server.

## License

MIT for the files in this repository. See `LICENSE`. The paid pack has its own buyer license.

## Contact

Scott Coffey, hello@sqlrig.com
