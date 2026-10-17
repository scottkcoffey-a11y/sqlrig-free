/*  expensive-queries.sql
    Purpose : Top queries by CPU / duration / logical reads. READ-ONLY.
              Section A = plan cache DMVs (any database, since last restart/plan eviction).
              Section B = Query Store (current database; needs Query Store ON — default ON for new DBs in 2022+).
    COMPAT  : SQL Server 2016+ (Query Store 2016+), Azure SQL MI
    Perms   : VIEW SERVER STATE (A); VIEW DATABASE STATE (B)
    Notes   : Plan-cache numbers vanish on restart / memory pressure / OPTION(RECOMPILE). Query Store persists.
*/
SET NOCOUNT ON;
DECLARE @Top int = 20;
DECLARE @OrderBy sysname = N'cpu';  -- cpu | duration | reads

/* ---- A. Plan cache ---- */
SELECT TOP (@Top)
    qs.execution_count,
    qs.total_worker_time  / 1000                         AS total_cpu_ms,
    qs.total_worker_time  / NULLIF(qs.execution_count,0) / 1000 AS avg_cpu_ms,
    qs.total_elapsed_time / 1000                         AS total_duration_ms,
    qs.total_elapsed_time / NULLIF(qs.execution_count,0) / 1000 AS avg_duration_ms,
    qs.total_logical_reads,
    qs.total_logical_reads / NULLIF(qs.execution_count,0)       AS avg_logical_reads,
    DB_NAME(t.dbid) AS database_name,
    OBJECT_NAME(t.objectid, t.dbid) AS object_name,
    SUBSTRING(t.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE qs.statement_end_offset END
          - qs.statement_start_offset)/2)+1) AS statement_text,
    qs.last_execution_time,
    qs.query_hash, qs.plan_handle
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) t
ORDER BY CASE @OrderBy WHEN N'duration' THEN qs.total_elapsed_time
                       WHEN N'reads'    THEN qs.total_logical_reads
                       ELSE qs.total_worker_time END DESC;

/* TEASER: Query Store path is in the paid pack (Section B).
   Enable Query Store and use sys.query_store_* for persistent history across restarts. */
