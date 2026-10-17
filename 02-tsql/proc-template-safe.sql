/*  proc-template-safe.sql
    Purpose : Production-safe stored procedure template (NOCOUNT, XACT_ABORT, TRY/CATCH, tran-count aware,
              validated parameters, return codes, @DryRun).
    COMPAT  : SQL Server 2016 SP1+ (CREATE OR ALTER) / Azure SQL MI
    Perms   : CREATE PROCEDURE + ALTER on schema. Callers need only EXECUTE (ownership chaining).
    Demo    : Creates dbo.usp_Template_ArchiveOrders and its demo tables ONLY IF THEY DON'T EXIST (in current DB).
              Run in a scratch database.
*/
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.DemoOrders', N'U') IS NULL
    CREATE TABLE dbo.DemoOrders (OrderId int IDENTITY PRIMARY KEY, Status varchar(20) NOT NULL, CreatedAt datetime2(0) NOT NULL DEFAULT SYSDATETIME());
IF OBJECT_ID(N'dbo.DemoOrdersArchive', N'U') IS NULL
    CREATE TABLE dbo.DemoOrdersArchive (OrderId int PRIMARY KEY, Status varchar(20) NOT NULL, CreatedAt datetime2(0) NOT NULL, ArchivedAt datetime2(0) NOT NULL DEFAULT SYSDATETIME());
GO

CREATE OR ALTER PROCEDURE dbo.usp_Template_ArchiveOrders
    @OlderThanDays int,
    @Status        varchar(20) = 'Closed',
    @DryRun        bit = 1,
    @RowsAffected  int = NULL OUTPUT
AS
/*  Return codes: 0 = success, 1 = invalid parameter, (errors are re-thrown, not swallowed) */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @OlderThanDays IS NULL OR @OlderThanDays < 1
    BEGIN
        RAISERROR(N'@OlderThanDays must be >= 1.', 16, 1);
        RETURN 1;
    END;

    DECLARE @Cutoff datetime2(0) = DATEADD(DAY, -@OlderThanDays, SYSDATETIME());

    IF @DryRun = 1
    BEGIN
        SELECT @RowsAffected = COUNT(*) FROM dbo.DemoOrders WHERE Status = @Status AND CreatedAt < @Cutoff;
        PRINT CONCAT(N'DRY RUN: would archive ', @RowsAffected, N' rows older than ', CONVERT(nvarchar(30), @Cutoff, 120));
        RETURN 0;
    END;

    DECLARE @StartedTran bit = 0;
    BEGIN TRY
        IF @@TRANCOUNT = 0 BEGIN BEGIN TRANSACTION; SET @StartedTran = 1; END;

        DECLARE @moved TABLE (OrderId int PRIMARY KEY);

        INSERT dbo.DemoOrdersArchive (OrderId, Status, CreatedAt)
        OUTPUT inserted.OrderId INTO @moved
        SELECT o.OrderId, o.Status, o.CreatedAt
        FROM dbo.DemoOrders o WITH (UPDLOCK, HOLDLOCK)
        WHERE o.Status = @Status AND o.CreatedAt < @Cutoff
          AND NOT EXISTS (SELECT 1 FROM dbo.DemoOrdersArchive a WHERE a.OrderId = o.OrderId);

        DELETE o FROM dbo.DemoOrders o JOIN @moved m ON m.OrderId = o.OrderId;   -- only rows proven archived
        SET @RowsAffected = @@ROWCOUNT;

        IF @StartedTran = 1 COMMIT TRANSACTION;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF @StartedTran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;   -- preserve original error number/line for the caller and Agent history
    END CATCH;
END;
GO

-- Test calls
DECLARE @rc int, @rows int;
EXEC @rc = dbo.usp_Template_ArchiveOrders @OlderThanDays = 30, @DryRun = 1, @RowsAffected = @rows OUTPUT;
SELECT @rc AS return_code, @rows AS rows_would_archive;
-- GRANT EXECUTE ON dbo.usp_Template_ArchiveOrders TO [app_role];   -- grant to a role, not a user
