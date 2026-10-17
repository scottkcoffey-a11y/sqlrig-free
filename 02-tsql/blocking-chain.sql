/*  blocking-chain.sql
    Purpose : Show current blocking chains and identify head blocker(s). READ-ONLY.
    COMPAT  : SQL Server 2016+ / Azure SQL MI
    Perms   : VIEW SERVER STATE (2022+: VIEW SERVER PERFORMANCE STATE)
    Notes   : Does not KILL anything. If you decide to KILL, record SPID + reason; KILL rolls back the open tran.
*/
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; -- DMV read only; avoids blocking on our own diagnostics

;WITH s AS (
    SELECT  es.session_id,
            ISNULL(er.blocking_session_id, 0)            AS blocking_session_id,
            es.login_name, es.host_name, es.program_name,
            DB_NAME(COALESCE(er.database_id, es.database_id)) AS database_name,
            er.status AS request_status, es.status AS session_status,
            er.wait_type, er.wait_time AS wait_time_ms, er.wait_resource,
            es.open_transaction_count,
            es.last_request_start_time, es.last_request_end_time,
            COALESCE(er.sql_handle, c.most_recent_sql_handle) AS sql_handle
    FROM sys.dm_exec_sessions es
    LEFT JOIN sys.dm_exec_requests er   ON er.session_id = es.session_id
    LEFT JOIN sys.dm_exec_connections c ON c.session_id  = es.session_id
    WHERE es.is_user_process = 1
),
blockers AS (   -- sessions that block someone but are not themselves blocked = head blockers
    SELECT DISTINCT s.session_id
    FROM s
    WHERE s.session_id IN (SELECT blocking_session_id FROM s WHERE blocking_session_id <> 0)
      AND s.blocking_session_id = 0
),
chain AS (
    SELECT s.session_id, s.blocking_session_id, 0 AS lvl,
           CAST(RIGHT('00000' + CAST(s.session_id AS varchar(10)), 5) AS varchar(4000)) AS chain_path
    FROM s JOIN blockers b ON b.session_id = s.session_id
    UNION ALL
    SELECT s.session_id, s.blocking_session_id, ch.lvl + 1,
           CAST(ch.chain_path + ' > ' + RIGHT('00000' + CAST(s.session_id AS varchar(10)), 5) AS varchar(4000))
    FROM s JOIN chain ch ON s.blocking_session_id = ch.session_id
    WHERE ch.lvl < 50
)
SELECT  ch.lvl AS chain_level,
        CASE WHEN ch.lvl = 0 THEN 'HEAD BLOCKER' ELSE 'blocked' END AS role,
        ch.chain_path,
        s.session_id, s.blocking_session_id, s.login_name, s.host_name, s.program_name, s.database_name,
        s.session_status, s.request_status, s.wait_type, s.wait_time_ms, s.wait_resource,
        s.open_transaction_count, s.last_request_start_time, s.last_request_end_time,
        LEFT(t.text, 4000) AS sql_text
FROM chain ch
JOIN s ON s.session_id = ch.session_id
OUTER APPLY sys.dm_exec_sql_text(s.sql_handle) t
ORDER BY ch.chain_path
OPTION (MAXRECURSION 100);

IF @@ROWCOUNT = 0 PRINT 'No blocking detected at ' + CONVERT(varchar(30), SYSDATETIME(), 121);
