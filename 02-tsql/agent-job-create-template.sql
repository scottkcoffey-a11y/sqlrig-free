/*  agent-job-create-template.sql
    Purpose : Create a single-step T-SQL SQL Server Agent job + category + daily schedule. Idempotent.
    COMPAT  : SQL Server 2016+ (incl. SQL Server on Linux with Agent enabled), Azure SQL MI
    Perms   : SQLAgentOperatorRole or sysadmin (msdb)
    Usage   : Edit the variables, run with @DryRun = 1 to preview, then @DryRun = 0.
              If the job already exists, nothing is changed (no silent overwrite).
    Rollback: EXEC msdb.dbo.sp_delete_job @job_name = N'<name>';   -- manual, after review
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DryRun       bit           = 1;
DECLARE @JobName      sysname       = N'DBA - Example Daily Job';
DECLARE @Category     sysname       = N'DBA Maintenance';
DECLARE @Description  nvarchar(512) = N'Created by AI Agent Toolkit template. Owner: DBA team.';
DECLARE @DatabaseName sysname       = N'master';
DECLARE @Command      nvarchar(max) = N'EXEC sys.sp_updatestats;';  -- prefer: EXEC dbo.YourProc;
DECLARE @OwnerLogin   sysname       = SUSER_SNAME(0x01);            -- sa (even if renamed)
DECLARE @StartTime    int           = 20000;                        -- HHMMSS -> 02:00:00
DECLARE @Enabled      tinyint       = 1;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    PRINT 'Job already exists: ' + @JobName + ' - no changes made.';
    RETURN;
END;

IF @DryRun = 1
BEGIN
    PRINT 'DRY RUN - would create:';
    PRINT '  category : ' + @Category;
    PRINT '  job      : ' + @JobName + ' (owner ' + @OwnerLogin + ')';
    PRINT '  step 1   : [' + @DatabaseName + '] ' + @Command;
    PRINT '  schedule : daily at ' + CAST(@StartTime AS varchar(10)) + ' (HHMMSS)';
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = @Category AND category_class = 1)
        EXEC msdb.dbo.sp_add_category @class = N'JOB', @type = N'LOCAL', @name = @Category;

    DECLARE @job_id uniqueidentifier;
    EXEC msdb.dbo.sp_add_job
         @job_name = @JobName, @enabled = @Enabled, @description = @Description,
         @category_name = @Category, @owner_login_name = @OwnerLogin,
         @notify_level_eventlog = 2, @job_id = @job_id OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
         @job_id = @job_id, @step_name = N'Step 1 - Run', @subsystem = N'TSQL',
         @database_name = @DatabaseName, @command = @Command,
         @retry_attempts = 1, @retry_interval = 5,
         @on_success_action = 1,  -- quit with success
         @on_fail_action    = 2;  -- quit with failure

    EXEC msdb.dbo.sp_add_jobschedule
         @job_id = @job_id, @name = N'Daily', @enabled = 1,
         @freq_type = 4, @freq_interval = 1, @active_start_time = @StartTime;

    EXEC msdb.dbo.sp_add_jobserver @job_id = @job_id, @server_name = N'(local)';

    COMMIT TRANSACTION;
    PRINT 'Created job: ' + @JobName;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- Verify
SELECT j.name, j.enabled, c.name AS category, s.step_id, s.step_name, s.subsystem, s.database_name
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
JOIN msdb.dbo.sysjobsteps s   ON s.job_id = j.job_id
WHERE j.name = @JobName;
