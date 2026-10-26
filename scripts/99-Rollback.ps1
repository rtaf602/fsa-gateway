<#
.SYNOPSIS
  Restore a standalone.xml backup made by 03-Install-Keystore.ps1 and restart Wildfly.
.PARAMETER Backup
  Path of the standalone.xml.bak-<timestamp> file. Defaults to the most recent backup.
.EXAMPLE
  .\scripts\99-Rollback.ps1
#>
[CmdletBinding()]
param(
    [string]$Backup,
    [switch]$NoRestart
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-GatewayConfig
if (-not (Test-IsAdmin)) { throw 'Run this script in an elevated (Administrator) PowerShell.' }

$confDir = Join-Path $cfg.WildflyPath 'standalone\configuration'
$xmlPath = Join-Path $confDir 'standalone.xml'
if (-not $Backup) {
    $b = Get-ChildItem $confDir -Filter 'standalone.xml.bak-*' | Sort-Object Name | Select-Object -Last 1
    if (-not $b) { throw "No standalone.xml.bak-* found in $confDir" }
    $Backup = $b.FullName
}
if (-not (Test-Path $Backup)) { throw "Backup $Backup not found." }

Write-Step "Restoring $Backup -> $xmlPath"
Copy-Item $xmlPath "$xmlPath.failed-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $Backup $xmlPath -Force
Write-Ok 'standalone.xml restored (the failed version was kept as standalone.xml.failed-*).'

if (-not $NoRestart) {
    Write-Step "Restarting service '$($cfg.WildflyServiceName)'"
    Restart-Service -Name $cfg.WildflyServiceName -Force
    Write-Ok 'Service restarted.'
}
