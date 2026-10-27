<#
.SYNOPSIS
  Check the Flysmart+ Gateway and repair the common problems automatically.
.DESCRIPTION
  Safe to run at any time (also from Task Scheduler at startup, see Install-GatewayAutoRepair.ps1):
    1. JAVA_HOME points to an existing java.exe (cannot repair - reports it)
    2. PostgreSQL service(s) running - starts them if stopped
    3. Wildfly service running       - starts it if stopped
    4. fsa-gateway.war and fsa-gateway-user.war deployed - creates <war>.dodeploy when the
       .deployed marker is missing (Wildfly runs with auto-deploy-zipped="false", so an
       interrupted or failed deployment never comes back by itself)
  Every run is appended to <WildflyPath>\standalone\log\gateway-repair.log
  Exit code: 0 = OK, 1 = repaired something, 2 = problem that needs a person.
.EXAMPLE
  .\scripts\Repair-Gateway.ps1
.EXAMPLE
  .\scripts\Repair-Gateway.ps1 -WildflyPath D:\Airbus\Wildfly -WaitMinutes 10
#>
[CmdletBinding()]
param(
    [string]$WildflyPath = 'C:\Airbus\Wildfly',
    [string]$ServiceName = 'Wildfly',
    [string[]]$Wars = @('fsa-gateway.war', 'fsa-gateway-user.war'),
    [int]$WaitMinutes = 8,
    [switch]$CheckOnly,
    [switch]$SkipServices   # testing only: skip Java/service checks
)

$ErrorActionPreference = 'Stop'
$deployDir = Join-Path $WildflyPath 'standalone\deployments'
$logFile = Join-Path $WildflyPath 'standalone\log\gateway-repair.log'
$script:exit = 0

function Log([string]$Level, [string]$Message) {
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $color = @{ OK = 'Green'; FIX = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }[$Level]
    Write-Host $line -ForegroundColor $color
    try { Add-Content -Path $logFile -Value $line -Encoding ASCII } catch { }
    if ($Level -eq 'FIX' -and $script:exit -lt 1) { $script:exit = 1 }
    if ($Level -eq 'FAIL') { $script:exit = 2 }
}

function Test-Marker([string]$War, [string]$Ext) { Test-Path (Join-Path $deployDir "$War.$Ext") }

Log INFO "=== Gateway check (CheckOnly=$CheckOnly) ==="
if (-not (Test-Path $deployDir)) { Log FAIL "Deployments folder not found: $deployDir (wrong -WildflyPath?)"; exit 2 }

if (-not $SkipServices) {
# 1. Java
$jh = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
if (-not $jh) {
    Log FAIL 'JAVA_HOME is not set (Installation Guide 5.1.2). Wildfly cannot start.'
} elseif (-not (Test-Path (Join-Path $jh 'bin\java.exe'))) {
    Log FAIL "JAVA_HOME=$jh but bin\java.exe is missing. Java was removed or updated: reinstall that JDK or fix JAVA_HOME, then restart the computer."
} else {
    Log OK "Java: $jh"
}

# 2. PostgreSQL
$pg = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'postgresql*' })
if ($pg.Count -eq 0) {
    Log INFO 'No local PostgreSQL service found (database may be on another server).'
}
foreach ($s in $pg) {
    if ($s.Status -eq 'Running') { Log OK "$($s.Name) running" }
    elseif ($CheckOnly) { Log FAIL "$($s.Name) is $($s.Status)" }
    else {
        try { Start-Service $s.Name; Log FIX "$($s.Name) was $($s.Status) - started" }
        catch { Log FAIL "$($s.Name) could not start: $($_.Exception.Message)" }
    }
}

# 3. Wildfly
$wf = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $wf) { Log FAIL "Service '$ServiceName' not found."; exit 2 }
if ($wf.Status -ne 'Running') {
    if ($CheckOnly) { Log FAIL "$ServiceName is $($wf.Status)" }
    else {
        try { Start-Service $ServiceName; Start-Sleep -Seconds 10; $wf.Refresh() } catch { }
        if ($wf.Status -eq 'Running') { Log FIX "$ServiceName was stopped - started" }
        else { Log FAIL "$ServiceName does not start. Check JAVA_HOME and standalone\log\service.*.log"; exit 2 }
    }
} else { Log OK "$ServiceName running" }
}

# 4. Deployments - wait while Wildfly is still starting, then repair missing markers
$deadline = (Get-Date).AddMinutes($WaitMinutes)
while ((Get-Date) -lt $deadline -and @($Wars | Where-Object { (Test-Marker $_ 'isdeploying') -or (Test-Marker $_ 'dodeploy') }).Count -gt 0) {
    Start-Sleep -Seconds 15
}

$triggered = @()
foreach ($war in $Wars) {
    if (-not (Test-Path (Join-Path $deployDir $war))) { Log FAIL "$war not found in deployments"; continue }
    if (Test-Marker $war 'deployed') { Log OK "$war deployed"; continue }
    if (Test-Marker $war 'isdeploying') { Log INFO "$war still deploying"; continue }
    if (Test-Marker $war 'skipdeploy') { Log INFO "$war has .skipdeploy - left alone"; continue }
    if (Test-Marker $war 'failed') {
        $reason = (Get-Content (Join-Path $deployDir "$war.failed") -Raw) -replace '\s+', ' '
        if ($reason.Length -gt 300) { $reason = $reason.Substring(0, 300) + '...' }
        Log INFO "$war.failed: $reason"
    }
    if ($CheckOnly) { Log FAIL "$war is NOT deployed"; continue }
    Remove-Item (Join-Path $deployDir "$war.failed"), (Join-Path $deployDir "$war.undeployed") -ErrorAction SilentlyContinue
    New-Item -Path (Join-Path $deployDir "$war.dodeploy") -ItemType File -Force | Out-Null
    $triggered += $war
    Log FIX "$war was not deployed - created $war.dodeploy"
}

# 5. Confirm the redeploys
if ($triggered.Count -gt 0) {
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    while ((Get-Date) -lt $deadline -and @($triggered | Where-Object { -not (Test-Marker $_ 'deployed') -and -not (Test-Marker $_ 'failed') }).Count -gt 0) {
        Start-Sleep -Seconds 15
    }
    foreach ($war in $triggered) {
        if (Test-Marker $war 'deployed') { Log OK "$war deployed after repair" }
        elseif (Test-Marker $war 'failed') { Log FAIL "$war failed again - see $war.failed and standalone\log\server.log" }
        else { Log FAIL "$war still not deployed after $WaitMinutes min" }
    }
}

Log INFO "=== Done (exit $script:exit) ==="
exit $script:exit
