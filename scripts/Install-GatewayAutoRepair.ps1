<#
.SYNOPSIS
  One-time setup on a Gateway computer to prevent / auto-repair the known problems.
.DESCRIPTION
  1. Wildfly service depends on PostgreSQL (keeps existing dependencies such as Tcpip/Afd)
     -> Windows starts PostgreSQL first and stops Wildfly first.
  2. Wildfly service restarts automatically if it crashes.
  3. Java auto-update disabled (an update removed the JDK used by JAVA_HOME).
  4. Scheduled task "FSA Gateway Auto Repair" (SYSTEM): runs Repair-Gateway.ps1
     5 minutes after every startup and every day at 07:00.
  Run as Administrator. Use -Uninstall to remove the scheduled task.
.EXAMPLE
  .\scripts\Install-GatewayAutoRepair.ps1
.EXAMPLE
  .\scripts\Install-GatewayAutoRepair.ps1 -WildflyPath D:\Airbus\Wildfly
#>
[CmdletBinding()]
param(
    [string]$WildflyPath = 'C:\Airbus\Wildfly',
    [string]$ServiceName = 'Wildfly',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$taskName = 'FSA Gateway Auto Repair'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an elevated (Administrator) PowerShell.'
}

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[OK] Scheduled task '$taskName' removed." -ForegroundColor Green
    return
}

# Copy the repair script to a fixed place so the task does not depend on this folder
$target = Join-Path $WildflyPath 'standalone\repair'
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Repair-Gateway.ps1') $target -Force
$repair = Join-Path $target 'Repair-Gateway.ps1'
Write-Host "[OK] Repair script: $repair" -ForegroundColor Green

# 1. Service dependency on PostgreSQL
$pg = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'postgresql*' } | Select-Object -ExpandProperty Name)
$svc = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"
if (-not $svc) { throw "Service '$ServiceName' not found." }
$current = @((Get-Service $ServiceName).ServicesDependedOn | Select-Object -ExpandProperty Name)
if ($pg.Count -eq 0) {
    Write-Host '[WARN] No local PostgreSQL service - dependency not set.' -ForegroundColor Yellow
} else {
    $new = @($current + $pg | Select-Object -Unique)
    if (@($pg | Where-Object { $current -notcontains $_ }).Count -gt 0) {
        & sc.exe config $ServiceName depend= ($new -join '/') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'sc.exe config failed' }
        Write-Host "[OK] $ServiceName now depends on: $($new -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "[OK] $ServiceName already depends on: $($current -join ', ')" -ForegroundColor Green
    }
    foreach ($p in $pg) { Set-Service $p -StartupType Automatic }
}
Set-Service $ServiceName -StartupType Automatic

# 2. Restart Wildfly automatically if it crashes (3 tries, 1 minute apart)
& sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
Write-Host "[OK] $ServiceName restarts automatically after a crash" -ForegroundColor Green

# 3. Disable Java auto-update (keeps the JDK referenced by JAVA_HOME in place)
foreach ($key in 'HKLM:\SOFTWARE\JavaSoft\Java Update\Policy', 'HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Update\Policy') {
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name EnableJavaUpdate -Value 0 -Type DWord
    Set-ItemProperty -Path $key -Name NotifyDownload -Value 0 -Type DWord
}
Write-Host '[OK] Java auto-update disabled' -ForegroundColor Green

# 4. Scheduled task
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$repair`" -WildflyPath `"$WildflyPath`" -ServiceName `"$ServiceName`""
$atStartup = New-ScheduledTaskTrigger -AtStartup
$atStartup.Delay = 'PT5M'
$daily = New-ScheduledTaskTrigger -Daily -At 7am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $atStartup, $daily -Settings $settings `
    -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Write-Host "[OK] Scheduled task '$taskName': 5 min after startup + daily 07:00" -ForegroundColor Green

Write-Host ''
Write-Host 'Running a check now...' -ForegroundColor Cyan
& $repair -WildflyPath $WildflyPath -ServiceName $ServiceName
