<#
.SYNOPSIS
  Restrict the Gateway HTTPS port to the VPN pool and office LAN (Windows Defender Firewall).
.DESCRIPTION
  - Creates/updates the inbound rule "FSA Gateway HTTPS (VPN/LAN only)" allowing TCP <HttpsPort>
    only from AllowedSubnets (config.ps1).
  - Lists other enabled inbound ALLOW rules that would still expose the Gateway ports
    (HTTPS, HTTP 8080, Wildfly admin 9990, PostgreSQL) to any address.
    With -DisableConflicting they are disabled (not deleted).
  Installation Guide 10.4 / 11.3: allow only the ports mandatory for Gateway operations.
  Run as Administrator. Use -WhatIf first to see what would change.
.EXAMPLE
  .\scripts\05-Set-Firewall.ps1 -WhatIf
.EXAMPLE
  .\scripts\05-Set-Firewall.ps1 -DisableConflicting
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$DisableConflicting,
    [int]$HttpPort = 8080,
    [int]$AdminPort = 9990,
    [int]$PostgresPort = 0
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-GatewayConfig
if (-not (Test-IsAdmin)) { throw 'Run this script in an elevated (Administrator) PowerShell.' }
if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) { throw 'NetSecurity module not available (Windows only).' }
$subnets = @($cfg.AllowedSubnets)
if (-not $subnets -or $subnets.Count -eq 0) { throw 'AllowedSubnets is empty in config.ps1' }
$https = [int]$cfg.HttpsPort
$name = 'FSA Gateway HTTPS (VPN/LAN only)'

Write-Step "Allow TCP $https from: $($subnets -join ', ')"
$existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
if ($existing) {
    if ($PSCmdlet.ShouldProcess($name, 'Update rule')) {
        $existing | Set-NetFirewallRule -Enabled True -Action Allow -Direction Inbound
        $existing | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $https
        $existing | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress $subnets
        Write-Ok "Rule updated: $name"
    }
} elseif ($PSCmdlet.ShouldProcess($name, 'Create rule')) {
    New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $https `
        -RemoteAddress $subnets -Profile Any -Description 'Flysmart+ Gateway - iPad sync over VPN/LAN' | Out-Null
    Write-Ok "Rule created: $name"
}

Write-Step 'Looking for other inbound rules that open Gateway ports to any address'
$ports = @($https, $HttpPort, $AdminPort) + @(if ($PostgresPort) { $PostgresPort })
$conflicts = @()
foreach ($r in Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True) {
    if ($r.DisplayName -eq $name) { continue }
    $addr = ($r | Get-NetFirewallAddressFilter).RemoteAddress
    if (@($addr) -notcontains 'Any') { continue }
    $pf = $r | Get-NetFirewallPortFilter
    $app = ($r | Get-NetFirewallApplicationFilter).Program
    $lp = @($pf.LocalPort)
    $portHit = ($lp -contains 'Any' -and $app -match 'java') -or @($lp | Where-Object { $ports -contains "$_" }).Count -gt 0
    if ($portHit) { $conflicts += [pscustomobject]@{ Name = $r.DisplayName; Ports = ($lp -join ','); Program = $app } }
}
if ($conflicts) {
    $conflicts | Format-Table -AutoSize | Out-String | Write-Host
    if ($DisableConflicting) {
        foreach ($c in $conflicts) {
            if ($PSCmdlet.ShouldProcess($c.Name, 'Disable rule')) {
                Get-NetFirewallRule -DisplayName $c.Name | Disable-NetFirewallRule
                Write-Ok "Disabled: $($c.Name)"
            }
        }
    } else {
        Write-Warn2 'These rules still expose Gateway ports to any address. Re-run with -DisableConflicting to disable them.'
    }
} else {
    Write-Ok 'No conflicting rules found.'
}
Write-Host "Note: ports $HttpPort and $AdminPort are not needed by the iPads - do not open them." -ForegroundColor DarkGray
