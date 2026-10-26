<#
.SYNOPSIS
  Step 1 - Create a new private key (alias mach9, PKCS12) and a CSR for the Gateway domain.
.DESCRIPTION
  Creates <WorkRoot>\<yyyyMMdd>\fsa-keystore-<yyyyMMdd>.jks and gateway.csr.
  Submit gateway.csr to the certificate authority (DV SSL, server type "Tomcat" or "Other").
  Run this again for every renewal: a new key is generated each time.
.EXAMPLE
  .\scripts\01-New-Csr.ps1
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-GatewayConfig
$domain = $cfg.Domain
# Country code is required by most commercial CAs (e.g. Namecheap)
$country = if ($cfg.ContainsKey('Country') -and $cfg.Country) { $cfg.Country } else { 'TH' }
$dname = "CN=$domain, C=$country"

$stamp = Get-Date -Format 'yyyyMMdd'
$dir = Join-Path $cfg.WorkRoot $stamp
$n = 1
while (Test-Path (Join-Path $dir 'state.json')) { $n++; $stamp = "$(Get-Date -Format 'yyyyMMdd')-$n"; $dir = Join-Path $cfg.WorkRoot $stamp }
New-Item -ItemType Directory -Path $dir -Force | Out-Null

$ksName = "fsa-keystore-$stamp.jks"
$ks  = Join-Path $dir $ksName
$csr = Join-Path $dir 'gateway.csr'

Write-Step "Domain      : $domain"
Write-Step "Work folder : $dir"
Write-Step "keytool     : $(Get-Keytool)"
$pw = Read-KeystorePassword -Confirm

Write-Step 'Generating RSA key pair (alias mach9, storetype PKCS12)'
Invoke-Keytool -Arguments @('-genkeypair', '-alias', $script:Alias, '-keyalg', 'RSA', '-keysize', "$($cfg.KeySize)",
    '-sigalg', 'SHA256withRSA', '-validity', '30', '-dname', $dname, '-ext', "SAN=dns:$domain",
    '-keystore', $ks, '-storetype', 'PKCS12', '-storepass', $pw, '-keypass', $pw) | Out-Null

Write-Step 'Creating CSR'
Invoke-Keytool -Arguments @('-certreq', '-alias', $script:Alias, '-sigalg', 'SHA256withRSA', '-ext', "SAN=dns:$domain",
    '-keystore', $ks, '-storetype', 'PKCS12', '-storepass', $pw, '-file', $csr) | Out-Null

@{
    Domain       = $domain
    Stamp        = $stamp
    KeystoreName = $ksName
    Keystore     = $ks
    Csr          = $csr
    Created      = (Get-Date).ToString('s')
} | ConvertTo-Json | Set-Content -Path (Join-Path $dir 'state.json') -Encoding UTF8

$csrText = Get-Content $csr -Raw
try { Set-Clipboard -Value $csrText; $clip = ' (copied to clipboard)' } catch { $clip = '' }

Write-Ok "Keystore created : $ks"
Write-Ok "CSR created      : $csr$clip"
Write-Host ''
Write-Host $csrText
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Paste the CSR above into the CA order (DV SSL, single domain; server type Tomcat/Other).'
Write-Host '  2. Validate the domain (DNS CNAME/TXT recommended).'
Write-Host '  3. Download the certificate files and run 02-Import-Certificate.ps1.'
Write-Warn2 "Keep $dir safe and outside the git repository - it contains the private key."
