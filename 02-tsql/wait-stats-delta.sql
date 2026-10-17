/*  wait-stats-delta.sql
    Purpose : Snapshot sys.dm_os_wait_stats, wait @Seconds, report the delta (top waits). READ-ONLY.
    COMPAT  : SQL Server 2016+ / Azure SQL MI
    Perms   : VIEW SERVER STATE
    Notes   : Uses a #temp table only. Does NOT clear wait stats (no DBCC SQLPERF ... CLEAR).
*/
SET NOCOUNT ON;
DECLARE @Seconds int = 10;   -- sample window (teaser default; paid pack uses 30)
DECLARE @Delay char(8) = CONVERT(char(8), DATEADD(SECOND, @Seconds, CAST('00:00:00' AS time)), 108);

IF OBJECT_ID('tempdb..#ws1') IS NOT NULL DROP TABLE #ws1;  -- session-scoped temp table only
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO #ws1 FROM sys.dm_os_wait_stats;

WAITFOR DELAY @Delay;

;WITH d AS (
    SELECT w.wait_type,
           w.waiting_tasks_count - ISNULL(a.waiting_tasks_count, 0) AS tasks,
           w.wait_time_ms        - ISNULL(a.wait_time_ms, 0)        AS wait_ms,
           w.signal_wait_time_ms - ISNULL(a.signal_wait_time_ms, 0) AS signal_ms
    FROM sys.dm_os_wait_stats w
    LEFT JOIN #ws1 a ON a.wait_type = w.wait_type
    WHERE w.wait_type NOT IN (  -- benign / idle waits
        N'BROKER_EVENTHANDLER',N'BROKER_RECEIVE_WAITFOR',N'BROKER_TASK_STOP',N'BROKER_TO_FLUSH',N'BROKER_TRANSMITTER',
        N'CHECKPOINT_QUEUE',N'CHKPT',N'CLR_AUTO_EVENT',N'CLR_MANUAL_EVENT',N'CLR_SEMAPHORE',N'DIRTY_PAGE_POLL',
        N'DISPATCHER_QUEUE_SEMAPHORE',N'FT_IFTS_SCHEDULER_IDLE_WAIT',N'FT_IFTSHC_MUTEX',N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        N'HADR_WORK_QUEUE',N'LAZYWRITER_SLEEP',N'LOGMGR_QUEUE',N'ONDEMAND_TASK_QUEUE',N'PREEMPTIVE_XE_GETTARGETSTATE',
        N'PWAIT_ALL_COMPONENTS_INITIALIZED',N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',N'QDS_ASYNC_QUEUE',
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',N'QDS_SHUTDOWN_QUEUE',
        N'REQUEST_FOR_DEADLOCK_SEARCH',N'RESOURCE_QUEUE',N'SERVER_IDLE_CHECK',N'SLEEP_BPOOL_FLUSH',N'SLEEP_DBSTARTUP',
        N'SLEEP_DCOMSTARTUP',N'SLEEP_MASTERDBREADY',N'SLEEP_MASTERMDREADY',N'SLEEP_MASTERUPGRADED',N'SLEEP_MSDBSTARTUP',
        N'SLEEP_SYSTEMTASK',N'SLEEP_TASK',N'SLEEP_TEMPDBSTARTUP',N'SNI_HTTP_ACCEPT',N'SOS_WORK_DISPATCHER',
        N'SP_SERVER_DIAGNOSTICS_SLEEP',N'SQLTRACE_BUFFER_FLUSH',N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        N'SQLTRACE_WAIT_ENTRIES',N'WAIT_FOR_RESULTS',N'WAITFOR',N'WAITFOR_TASKSHUTDOWN',N'WAIT_XTP_HOST_WAIT',
        N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',N'WAIT_XTP_CKPT_CLOSE',N'XE_DISPATCHER_JOIN',N'XE_DISPATCHER_WAIT',
        N'XE_TIMER_EVENT',N'XE_LIVE_TARGET_TVF',N'BROKER_DISPATCHER',N'PVS_PREALLOCATE')
)
SELECT TOP (20)
       wait_type, tasks, wait_ms, signal_ms,
       wait_ms - signal_ms AS resource_ms,
       CAST(100.0 * wait_ms / NULLIF(SUM(wait_ms) OVER (), 0) AS decimal(5,2)) AS pct_of_window,
       CAST(1.0 * wait_ms / NULLIF(tasks, 0) AS decimal(18,2)) AS avg_wait_ms,
       @Seconds AS sample_seconds
FROM d
WHERE wait_ms > 0
ORDER BY wait_ms DESC;

DROP TABLE #ws1;
