#Requires -Version 5.1
<#
.SYNOPSIS
  Connection smoke test: SELECT @@VERSION + database ONLINE check.
.NOTES
  COMPAT: Windows PowerShell 5.1 / PowerShell 7+. Optional SqlServer module; falls back to System.Data.SqlClient.
  Auth: Integrated by default. Pass -Credential for SQL auth (never hardcode passwords).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ServerInstance,
    [string]$Database = 'master',
    [pscredential]$Credential,
    [int]$ConnectionTimeoutSec = 15,
    [switch]$TrustServerCertificate
)

$ErrorActionPreference = 'Stop'
$result = [ordered]@{ ServerInstance = $ServerInstance; Database = $Database; Ok = $false; Version = $null; State = $null; Error = $null }

function New-ToolkitSqlConnection {
    param([string]$Server,[string]$Db,[pscredential]$Cred,[int]$Timeout,[bool]$Trust)
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b['Data Source'] = $Server; $b['Initial Catalog'] = $Db; $b['Connect Timeout'] = $Timeout
    $b['Encrypt'] = $true
    if ($Trust) { $b['TrustServerCertificate'] = $true }
    if ($Cred) {
        $b['Integrated Security'] = $false
        $b['User ID'] = $Cred.UserName
        $b['Password'] = $Cred.GetNetworkCredential().Password
    } else {
        $b['Integrated Security'] = $true
    }
    $conn = New-Object System.Data.SqlClient.SqlConnection $b.ConnectionString
    return $conn
}

if (-not $PSCmdlet.ShouldProcess("$ServerInstance / $Database", 'Open connection and run smoke queries')) {
    Write-Host "WhatIf: would connect to $ServerInstance / $Database and SELECT @@VERSION + database state."
    return [pscustomobject]$result
}

try {
    $conn = New-ToolkitSqlConnection -Server $ServerInstance -Db $Database -Cred $Credential -Timeout $ConnectionTimeoutSec -Trust:$TrustServerCertificate.IsPresent
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 'SELECT @@VERSION AS Ver, DATABASEPROPERTYEX(@db, ''Status'') AS State;'
    $null = $cmd.Parameters.Add('@db', [System.Data.SqlDbType]::NVarChar, 128)
    $cmd.Parameters['@db'].Value = $Database
    $r = $cmd.ExecuteReader()
    if ($r.Read()) {
        $result.Version = [string]$r['Ver']
        $result.State   = [string]$r['State']
        $result.Ok      = ($result.State -eq 'ONLINE')
    }
    $r.Close(); $conn.Close()
    if (-not $result.Ok) { throw "Database '$Database' state is '$($result.State)', expected ONLINE." }
} catch {
    $result.Error = $_.Exception.Message
    $result.Ok = $false
    Write-Error $_
    exit 1
} finally {
    if ($conn -and $conn.State -ne 'Closed') { $conn.Dispose() }
}

[pscustomobject]$result | Format-List
if (-not $result.Ok) { exit 1 }
