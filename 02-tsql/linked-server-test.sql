/*  linked-server-test.sql
    Purpose : Connectivity + latency smoke test for one or all linked servers. READ-ONLY.
    COMPAT  : SQL Server 2016+ / Azure SQL MI
    Perms   : Login must have a mapping on each linked server tested.
*/
SET NOCOUNT ON;
DECLARE @LinkedName sysname = NULL;   -- NULL = test all linked servers

DECLARE @results TABLE (linked_server sysname, data_source nvarchar(4000), ok bit, ms int, error_message nvarchar(4000));
DECLARE @name sysname, @src nvarchar(4000), @t0 datetime2(3), @ret int;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name, data_source FROM sys.servers
    WHERE is_linked = 1 AND (@LinkedName IS NULL OR name = @LinkedName);
OPEN c; FETCH NEXT FROM c INTO @name, @src;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @t0 = SYSDATETIME();
    BEGIN TRY
        EXEC @ret = master.sys.sp_testlinkedserver @servername = @name;
        INSERT @results VALUES (@name, @src, 1, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), NULL);
    END TRY
    BEGIN CATCH
        INSERT @results VALUES (@name, @src, 0, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), ERROR_MESSAGE());
    END CATCH;
    FETCH NEXT FROM c INTO @name, @src;
END
CLOSE c; DEALLOCATE c;

IF NOT EXISTS (SELECT 1 FROM @results)
    PRINT 'No linked servers matched.';
SELECT linked_server, data_source, CASE ok WHEN 1 THEN 'OK' ELSE 'FAIL' END AS status, ms AS elapsed_ms, error_message
FROM @results ORDER BY ok, linked_server;
