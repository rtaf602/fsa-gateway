<#
.SYNOPSIS
  One command: create/renew the SSL certificate of the Flysmart+ Gateway for use on the office LAN.
.DESCRIPTION
  Run on the Gateway computer in an Administrator PowerShell:
    1. Creates the unit root CA the first time (reused at every renewal)
    2. Creates a new key + certificate for <Domain> (alias mach9, PKCS12, 800 days)
    3. Installs it in Wildfly (standalone.xml backed up) and restarts the service
    4. Tests the HTTPS connection
    5. Puts the root CA file for the iPads in <WorkRoot>\ipad\
  Renewal (about every 2 years): run the same command again - iPads do not need anything.
.PARAMETER NoRestart
  Do not restart Wildfly (restart it yourself later).
.PARAMETER ShowDetails
  Show the full output of every step.
.EXAMPLE
  .\Setup-LanSsl.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoRestart,
    [switch]$ShowDetails
)

$ErrorActionPreference = 'Stop'
$scripts = Join-Path $PSScriptRoot 'scripts'
. (Join-Path $scripts 'Common.ps1')
$cfg = Get-GatewayConfig
if (-not (Test-IsAdmin)) { throw 'Right-click PowerShell > "Run as administrator", then run this script again.' }

function Invoke-Step([string]$Title, [string]$Script, [hashtable]$Params = @{}) {
    Write-Step $Title
    $path = Join-Path $scripts $Script
    if ($ShowDetails) { & $path @Params } else { & $path @Params 6>$null | Out-Null }
}

Write-Host ''
Write-Host "Flysmart+ Gateway SSL setup for $($cfg.Domain)" -ForegroundColor White
Write-Host ''

# Check the name points to this computer
try {
    $resolved = @([Net.Dns]::GetHostAddresses($cfg.Domain) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.ToString() })
} catch { $resolved = @() }
$local = @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | ForEach-Object {
    $_.GetIPProperties().UnicastAddresses } | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.Address.ToString() })
if ($resolved.Count -eq 0) {
    Write-Warn2 "$($cfg.Domain) does not resolve yet. Add it to the office router/DNS (see README) before testing on iPads."
} elseif (-not ($resolved | Where-Object { $local -contains $_ })) {
    Write-Warn2 "$($cfg.Domain) resolves to $($resolved -join ', ') but this computer is $($local -join ', ')."
} else {
    Write-Ok "$($cfg.Domain) -> $($resolved -join ', ') (this computer)"
}

$caKs = Join-Path $cfg.CaRoot 'root-ca.p12'
$firstTime = -not (Test-Path $caKs)
if ($firstTime) {
    Write-Host 'Choose a password (8+ characters, no < > " = / # : & '' \ or spaces).' -ForegroundColor Cyan
    Write-Host 'Write it down and keep it safe: it is needed again for renewal.' -ForegroundColor Cyan
    $env:FSA_KEYSTORE_PASSWORD = Read-KeystorePassword -Confirm
} else {
    Write-Host 'Renewal: enter the same password used the first time.' -ForegroundColor Cyan
    $env:FSA_KEYSTORE_PASSWORD = Read-KeystorePassword
}

try {
    if ($firstTime) { Invoke-Step '1/5 Creating unit root CA (first time only)' 'ca/10-New-RootCA.ps1' }
    else            { Write-Step '1/5 Using existing unit root CA' }

    Invoke-Step '2/5 Creating new key and certificate request' '01-New-Csr.ps1'
    $dir = Get-WorkDir -Config $cfg
    $csr = Join-Path $dir 'gateway.csr'
    $crt = Join-Path $dir 'gateway.crt'
    $base = ($cfg.CaName -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower()
    $rootPem = Join-Path $cfg.CaRoot "$base.pem"
    $rootCer = Join-Path $cfg.CaRoot "$base.cer"

    Invoke-Step '3/5 Signing and checking the certificate' 'ca/11-Sign-GatewayCsr.ps1' @{ CsrFile = $csr }
    Invoke-Step '    Importing into keystore' '02-Import-Certificate.ps1' @{ CertFile = $crt; ChainFile = $rootPem; NoPrompt = $true }

    $p = @{}; if ($NoRestart) { $p.NoRestart = $true }
    Invoke-Step '4/5 Installing in Wildfly (standalone.xml backed up)' '03-Install-Keystore.ps1' $p
} catch {
    Write-Host ''
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Run again with -ShowDetails to see every step. If Wildfly does not start: .\scripts\99-Rollback.ps1' -ForegroundColor Yellow
    exit 1
} finally {
    Remove-Item Env:\FSA_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
}

$test = 0
if ($NoRestart) {
    Write-Warn2 "5/5 Skipped test: restart the '$($cfg.WildflyServiceName)' service, then run .\scripts\04-Test-Gateway.ps1 -Server 127.0.0.1 -CaFile `"$rootPem`""
} else {
    Write-Step '5/5 Testing HTTPS'
    & (Join-Path $scripts '04-Test-Gateway.ps1') -Server 127.0.0.1 -CaFile $rootPem
    $test = $LASTEXITCODE
}

# File for the iPads
$ipadDir = Join-Path $cfg.WorkRoot 'ipad'
New-Item -ItemType Directory -Path $ipadDir -Force | Out-Null
$ipadCer = Join-Path $ipadDir "$base.cer"
Copy-Item $rootCer $ipadCer -Force
$thumb = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $rootCer).Thumbprint
$state = Get-State $dir

Write-Host ''
if ($test -eq 2) { Write-Host 'Certificate installed, but the HTTPS test failed - see above.' -ForegroundColor Red }
else { Write-Host 'Done.' -ForegroundColor Green }
Write-Host "  Gateway address for FS+ Manager : $($cfg.Domain)  (port $($cfg.HttpsPort))"
Write-Host "  Certificate valid until          : $(([datetime]$state.NotAfter).ToString('yyyy-MM-dd'))  -> run this script again before then"
if ($firstTime) {
    Write-Host "  File to install on every iPad    : $ipadCer"
    Write-Host "  Root CA fingerprint (SHA-1)      : $thumb"
    Write-Host '  See README: "Install on the iPads". Back up the folder:' $cfg.CaRoot
} else {
    Write-Host '  iPads already trust the unit root CA - nothing to do on the iPads.'
}
exit $test
