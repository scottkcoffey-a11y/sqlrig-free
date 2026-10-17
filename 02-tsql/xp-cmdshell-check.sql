/*  xp-cmdshell-check.sql
    Purpose : Read-only surface-area audit: xp_cmdshell, Ole Automation, CLR, Database Mail XPs,
              remote access, Ad Hoc Distributed Queries, and related Agent settings.
              DOES NOT enable or disable anything.
    COMPAT  : SQL Server 2016+ / Azure SQL MI (some options are N/A on Azure SQL DB)
    Perms   : VIEW SERVER STATE; viewing sys.configurations needs VIEW SERVER STATE (or public by default)
*/
SET NOCOUNT ON;

SELECT name, CAST(value_in_use AS int) AS value_in_use, CAST(value AS int) AS configured_value,
       CASE WHEN name IN (N'xp_cmdshell', N'Ole Automation Procedures', N'clr enabled', N'remote access',
                          N'Ad Hoc Distributed Queries') AND CAST(value_in_use AS int) = 1
            THEN 'REVIEW - elevated surface area'
            WHEN name = N'clr strict security' AND CAST(value_in_use AS int) = 0
            THEN 'REVIEW - CLR assemblies not forced SAFE'
            ELSE 'ok / expected'
       END AS assessment
FROM sys.configurations
WHERE name IN (
    N'xp_cmdshell', N'Ole Automation Procedures', N'clr enabled', N'clr strict security',
    N'Database Mail XPs', N'remote access', N'remote admin connections',
    N'Ad Hoc Distributed Queries', N'scan for startup procs', N'Agent XPs',
    N'cross db ownership chaining'
)
ORDER BY name;

PRINT '=== Proxy accounts that can run CmdExec / PowerShell (review credentials) ===';
SELECT p.name AS proxy_name, c.name AS credential_name, c.credential_identity,
       ISNULL(STRING_AGG(s.subsystem, ','), '') AS subsystems
FROM msdb.dbo.sysproxies p
JOIN sys.credentials c ON c.credential_id = p.credential_id
LEFT JOIN msdb.dbo.sysproxysubsystem ps ON ps.proxy_id = p.proxy_id
LEFT JOIN msdb.dbo.syssubsystems s ON s.subsystem_id = ps.subsystem_id
WHERE p.enabled = 1
GROUP BY p.name, c.name, c.credential_identity;

PRINT 'Remediation (DO NOT run blindly) — to disable xp_cmdshell:';
PRINT '  EXEC sp_configure ''show advanced options'', 1; RECONFIGURE;';
PRINT '  EXEC sp_configure ''xp_cmdshell'', 0; RECONFIGURE;';
PRINT 'Prefer SQL Server Agent with a least-privilege proxy over enabling xp_cmdshell.';
