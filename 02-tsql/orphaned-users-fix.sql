/*  orphaned-users-fix.sql
    Purpose : Detect SQL users whose SID no longer matches a login after a restore; optionally remap.
              Windows users/groups and contained users are reported but NOT auto-fixed.
    COMPAT  : SQL Server 2016+ / Azure SQL MI (ALTER USER ... WITH LOGIN)
    Perms   : ALTER ANY USER (to fix). Detection needs VIEW DEFINITION.
    Safety  : @DryRun = 1 by default. Remap only when the login name equals the user name OR you supply
              an explicit mapping table. Never creates logins.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @DryRun bit = 1;

PRINT '=== Orphaned SQL users in ' + DB_NAME() + ' ===';
SELECT dp.name AS user_name, dp.sid AS user_sid, dp.type_desc,
       CASE WHEN sp.name IS NULL THEN 'ORPHANED' ELSE 'OK (login=' + sp.name + ')' END AS status,
       sp.name AS matching_login_by_sid
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON sp.sid = dp.sid
WHERE dp.type IN ('S')                    -- SQL users only
  AND dp.authentication_type = 1         -- INSTANCE (login-mapped SQL user). 0 = NONE (WITHOUT LOGIN), 2 = DATABASE (contained), 3 = WINDOWS
  AND dp.sid IS NOT NULL AND dp.sid <> 0x00
  AND dp.name NOT IN (N'dbo', N'guest', N'INFORMATION_SCHEMA', N'sys')
  AND sp.sid IS NULL
ORDER BY dp.name;

PRINT '=== Users created WITHOUT LOGIN (by design, not orphans; never remapped) ===';
SELECT dp.name, dp.type_desc, dp.authentication_type_desc
FROM sys.database_principals dp
WHERE dp.type = 'S' AND dp.authentication_type = 0
  AND dp.name NOT IN (N'dbo', N'guest', N'INFORMATION_SCHEMA', N'sys');

PRINT '=== Windows / contained users present (reported only; not remapped by this script) ===';
SELECT dp.name, dp.type_desc, dp.authentication_type_desc
FROM sys.database_principals dp
WHERE dp.type IN ('U','G','S') AND dp.authentication_type IN (2, 3)
  AND dp.name NOT IN (N'dbo', N'guest');

IF @DryRun = 1
BEGIN
    PRINT 'DRY RUN: remapping skipped. Set @DryRun = 0 to ALTER USER ... WITH LOGIN when a same-named login exists.';
    RETURN;
END;

DECLARE @u sysname, @sql nvarchar(max), @ok int = 0, @skip int = 0;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT dp.name
    FROM sys.database_principals dp
    LEFT JOIN sys.server_principals sp ON sp.sid = dp.sid
    WHERE dp.type = 'S' AND dp.authentication_type = 1
      AND dp.sid IS NOT NULL AND dp.sid <> 0x00
      AND dp.name NOT IN (N'dbo', N'guest', N'INFORMATION_SCHEMA', N'sys')
      AND sp.sid IS NULL;
OPEN c; FETCH NEXT FROM c INTO @u;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @u AND type = 'S')
    BEGIN
        SET @sql = N'ALTER USER ' + QUOTENAME(@u) + N' WITH LOGIN = ' + QUOTENAME(@u) + N';';
        BEGIN TRY EXEC sys.sp_executesql @sql; SET @ok += 1; PRINT 'Remapped: ' + @u; END TRY
        BEGIN CATCH PRINT 'FAILED ' + @u + ': ' + ERROR_MESSAGE(); END CATCH;
    END
    ELSE BEGIN SET @skip += 1; PRINT 'SKIP (no same-named login): ' + @u; END;
    FETCH NEXT FROM c INTO @u;
END
CLOSE c; DEALLOCATE c;
PRINT CONCAT('Remapped=', @ok, ', skipped=', @skip);
