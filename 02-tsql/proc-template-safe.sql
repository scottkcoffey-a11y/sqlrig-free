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
    @BatchSize     int    = 2000,        -- keep < 5000 to avoid lock escalation
    @MaxRows       bigint = 1000000,     -- hard stop per run
    @DryRun        bit = 1,
    @RowsAffected  int = NULL OUTPUT
AS
/*  Return codes: 0 = success, 1 = invalid parameter, (errors are re-thrown, not swallowed)
    Writes are batched: each batch archives + deletes TOP (@BatchSize) rows in its own short transaction. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @DryRun IS NULL
    BEGIN
        RAISERROR(N'@DryRun must be 0 or 1 (NULL is rejected - dry-run flags fail closed).', 16, 1);
        RETURN 1;
    END;
    IF @OlderThanDays IS NULL OR @OlderThanDays < 1
    BEGIN
        RAISERROR(N'@OlderThanDays must be >= 1.', 16, 1);
        RETURN 1;
    END;
    IF @BatchSize IS NULL OR @BatchSize NOT BETWEEN 1 AND 4999 OR @MaxRows IS NULL OR @MaxRows < 1
    BEGIN
        RAISERROR(N'@BatchSize must be 1-4999 and @MaxRows >= 1.', 16, 1);
        RETURN 1;
    END;

    DECLARE @Cutoff datetime2(0) = DATEADD(DAY, -@OlderThanDays, SYSDATETIME());

    IF ISNULL(@DryRun, 1) = 1   -- NULL already rejected above; ISNULL keeps this fail-closed if edited
    BEGIN
        SELECT @RowsAffected = COUNT(*) FROM dbo.DemoOrders WHERE Status = @Status AND CreatedAt < @Cutoff;
        PRINT CONCAT(N'DRY RUN: would archive ', @RowsAffected, N' rows older than ', CONVERT(nvarchar(30), @Cutoff, 120),
                     N' in batches of ', @BatchSize, N' (cap ', @MaxRows, N').');
        RETURN 0;
    END;

    -- Batched path requires owning the transaction (one short transaction per batch).
    IF @@TRANCOUNT > 0
    BEGIN
        RAISERROR(N'Call with no open transaction: this procedure commits per batch.', 16, 1);
        RETURN 1;
    END;

    DECLARE @Rows int = 1, @Total bigint = 0, @Batch int = 0;
    DECLARE @moved TABLE (OrderId int PRIMARY KEY);

    WHILE @Rows > 0 AND @Total < @MaxRows
    BEGIN
        DELETE @moved;
        BEGIN TRY
            BEGIN TRANSACTION;

            INSERT dbo.DemoOrdersArchive (OrderId, Status, CreatedAt)
            OUTPUT inserted.OrderId INTO @moved
            SELECT TOP (@BatchSize) o.OrderId, o.Status, o.CreatedAt
            FROM dbo.DemoOrders o WITH (UPDLOCK, READPAST)
            WHERE o.Status = @Status AND o.CreatedAt < @Cutoff
              AND NOT EXISTS (SELECT 1 FROM dbo.DemoOrdersArchive a WHERE a.OrderId = o.OrderId)
            ORDER BY o.OrderId;

            DELETE o FROM dbo.DemoOrders o JOIN @moved m ON m.OrderId = o.OrderId;   -- only rows proven archived
            SET @Rows = @@ROWCOUNT;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            THROW;   -- preserve original error number/line for the caller and Agent history
        END CATCH;

        SET @Total += @Rows; SET @Batch += 1;
        IF @Rows > 0 RAISERROR('Batch %d: %d rows archived', 0, 1, @Batch, @Rows) WITH NOWAIT;
    END;

    SET @RowsAffected = CAST(@Total AS int);
    RETURN 0;
END;
GO

-- Test calls
DECLARE @rc int, @rows int;
EXEC @rc = dbo.usp_Template_ArchiveOrders @OlderThanDays = 30, @DryRun = 1, @RowsAffected = @rows OUTPUT;
SELECT @rc AS return_code, @rows AS rows_would_archive;
-- GRANT EXECUTE ON dbo.usp_Template_ArchiveOrders TO [app_role];   -- grant to a role, not a user
