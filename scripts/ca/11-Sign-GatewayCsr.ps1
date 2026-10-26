<#
.SYNOPSIS
  Private CA step 2 - Sign the Gateway CSR with the root CA (iOS-compliant server cert).
.DESCRIPTION
  Issues a certificate valid CertValidityDays (max 825 for iOS) with:
    SAN = DNS:<Domain>, EKU = serverAuth, KU = digitalSignature,keyEncipherment,
    BasicConstraints = CA:false, SHA-256.
  Output: gateway.crt next to the CSR. Then on the Gateway run:
    .\scripts\02-Import-Certificate.ps1 -CertFile gateway.crt -ChainFile <CaRoot>\<name>.pem
.PARAMETER CsrFile
  gateway.csr produced by 01-New-Csr.ps1.
.EXAMPLE
  .\scripts\ca\11-Sign-GatewayCsr.ps1 -CsrFile E:\transfer\gateway.csr
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$CsrFile)

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common.ps1')
$cfg = Get-GatewayConfig
$caKs = Join-Path $cfg.CaRoot 'root-ca.p12'
if (-not (Test-Path $caKs)) { throw "Root CA not found: $caKs (run 10-New-RootCA.ps1 or plug in the CA drive)." }
$days = [int]$cfg.CertValidityDays
if ($days -gt 825) { throw 'CertValidityDays must be <= 825 (iOS limit for TLS server certificates).' }

$CsrFile = (Resolve-Path $CsrFile).Path
$domain = $cfg.Domain

Write-Step 'Checking CSR'
$req = (Invoke-Keytool -Quiet -Arguments @('-printcertreq', '-v', '-file', $CsrFile)) -join "`n"
if ($req -notmatch "CN=$([regex]::Escape($domain))\b") { throw "CSR subject is not CN=$domain. Check config.ps1 or regenerate the CSR." }
Write-Ok "CSR subject CN=$domain"

$out = Join-Path (Split-Path -Parent $CsrFile) 'gateway.crt'
$pw = Read-KeystorePassword

Write-Step "Signing for $days days"
Invoke-Keytool -Quiet -Arguments @('-gencert', '-rfc', '-alias', 'rootca', '-keystore', $caKs, '-storetype', 'PKCS12',
    '-storepass', $pw, '-infile', $CsrFile, '-outfile', $out, '-sigalg', 'SHA256withRSA', '-validity', "$days",
    '-ext', "SAN=dns:$domain", '-ext', 'EKU=serverAuth', '-ext', 'KU:critical=digitalSignature,keyEncipherment',
    '-ext', 'BC:critical=ca:false') | Out-Null

$c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $out
$base = ($cfg.CaName -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower()
Write-Ok "Certificate: $out"
Write-Host "    Subject : $($c.Subject)"
Write-Host "    SAN     : $((Get-SanDnsNames $c) -join ', ')"
Write-Host "    Valid   : $($c.NotBefore) -> $($c.NotAfter)"
Write-Host ''
Write-Host 'Next (on the Gateway):' -ForegroundColor Cyan
Write-Host "  .\scripts\02-Import-Certificate.ps1 -CertFile gateway.crt -ChainFile $base.pem"
Write-Host '  keytool will say the top-level certificate is not trusted (expected for a private CA):'
Write-Host '  check the root fingerprint, answer yes, then run 03-Install-Keystore.ps1.'
Write-Warn2 "Put a reminder ~1 month before $($c.NotAfter.ToString('yyyy-MM-dd')) to renew."
