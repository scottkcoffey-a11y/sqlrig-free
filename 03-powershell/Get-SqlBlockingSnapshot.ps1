#Requires -Version 5.1
<#
.SYNOPSIS
  Capture the current blocking chain to CSV and/or JSON for tickets.
.NOTES
  Embeds a compact version of 02-tsql/blocking-chain.sql. Read-only. -WhatIf shows the target path only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ServerInstance,
    [string]$OutputPath = (Join-Path (Get-Location) ("blocking_{0:yyyyMMdd_HHmmss}" -f (Get-Date))),
    [ValidateSet('Csv')][string]$Format = 'Csv',  # teaser: CSV only; paid pack adds Json/Both
    [pscredential]$Credential,
    [switch]$TrustServerCertificate
)

$ErrorActionPreference = 'Stop'
$sql = @'
SET NOCOUNT ON;
SELECT  er.session_id, er.blocking_session_id, es.login_name, es.host_name, es.program_name,
        DB_NAME(er.database_id) AS database_name, er.wait_type, er.wait_time AS wait_time_ms,
        er.wait_resource, es.open_transaction_count,
        LEFT(t.text, 4000) AS sql_text
FROM sys.dm_exec_requests er
JOIN sys.dm_exec_sessions es ON es.session_id = er.session_id
OUTER APPLY sys.dm_exec_sql_text(er.sql_handle) t
WHERE er.blocking_session_id <> 0
   OR er.session_id IN (SELECT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
ORDER BY er.blocking_session_id, er.session_id;
'@

if (-not $PSCmdlet.ShouldProcess($ServerInstance, "Capture blocking snapshot to $OutputPath.*")) {
    Write-Host "WhatIf: would write $Format to $OutputPath.*"; return
}

$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$csb['Data Source'] = $ServerInstance; $csb['Initial Catalog'] = 'master'
$csb['Encrypt'] = $true; $csb['Connect Timeout'] = 15
if ($TrustServerCertificate) { $csb['TrustServerCertificate'] = $true }
if ($Credential) {
    $csb['Integrated Security'] = $false
    $csb['User ID'] = $Credential.UserName
    $csb['Password'] = $Credential.GetNetworkCredential().Password
} else { $csb['Integrated Security'] = $true }

$conn = New-Object System.Data.SqlClient.SqlConnection $csb.ConnectionString
$da = New-Object System.Data.SqlClient.SqlDataAdapter ($sql, $conn)
$dt = New-Object System.Data.DataTable
[void]$da.Fill($dt)

$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

$rows = foreach ($r in $dt.Rows) {
    $o = [ordered]@{}
    foreach ($c in $dt.Columns) { $o[$c.ColumnName] = $r[$c] }
    [pscustomobject]$o
}

if ($Format -in 'Csv','Both') {
    $csv = "$OutputPath.csv"
    $rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    Write-Host "Wrote $csv ($($rows.Count) rows)"
}
if ($Format -in 'Json','Both') {
    $json = "$OutputPath.json"
    $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $json -Encoding UTF8
    Write-Host "Wrote $json ($($rows.Count) rows)"
}
if ($rows.Count -eq 0) { Write-Host 'No blocking detected.' }
