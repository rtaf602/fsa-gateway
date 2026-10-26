<#
.SYNOPSIS
  Private CA step 1 - Create the root CA (run ONCE, ideally on an admin PC, not the Gateway).
.DESCRIPTION
  Creates <CaRoot>\root-ca.p12 (RSA 4096, SHA-256, CA:true pathlen:0) and exports:
    <CaRoot>\<name>.cer  (DER)  -> upload to MDM as a Certificate payload for the iPads
    <CaRoot>\<name>.pem  (PEM)  -> used as -ChainFile by 02-Import-Certificate.ps1
  The root CA private key can impersonate the Gateway: keep CaRoot on an encrypted
  removable drive, store the password separately, and keep an offline backup copy.
.EXAMPLE
  .\scripts\ca\10-New-RootCA.ps1
#>
[CmdletBinding()]
param()

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common.ps1')
$cfg = Get-GatewayConfig
$caKs = Join-Path $cfg.CaRoot 'root-ca.p12'
if (Test-Path $caKs) { throw "Root CA already exists: $caKs. Do not create a new one unless you plan to re-deploy it to all iPads." }
New-Item -ItemType Directory -Path $cfg.CaRoot -Force | Out-Null

$base = ($cfg.CaName -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower()
$cer = Join-Path $cfg.CaRoot "$base.cer"
$pem = Join-Path $cfg.CaRoot "$base.pem"
$days = [int]$cfg.CaValidityYears * 365

Write-Step "Creating root CA '$($cfg.CaName)' valid $($cfg.CaValidityYears) years in $($cfg.CaRoot)"
Write-Host '    Use a long password (16+ chars) different from the Gateway keystore password.' -ForegroundColor DarkGray
$pw = Read-KeystorePassword -Confirm

Invoke-Keytool -Arguments @('-genkeypair', '-alias', 'rootca', '-keyalg', 'RSA', '-keysize', '4096', '-sigalg', 'SHA256withRSA',
    '-validity', "$days", '-dname', "CN=$($cfg.CaName)",
    '-ext', 'BC:critical=ca:true,pathlen:0', '-ext', 'KU:critical=keyCertSign,cRLSign',
    '-keystore', $caKs, '-storetype', 'PKCS12', '-storepass', $pw, '-keypass', $pw) | Out-Null

Invoke-Keytool -Quiet -Arguments @('-exportcert', '-alias', 'rootca', '-keystore', $caKs, '-storetype', 'PKCS12',
    '-storepass', $pw, '-file', $cer) | Out-Null
Invoke-Keytool -Quiet -Arguments @('-exportcert', '-rfc', '-alias', 'rootca', '-keystore', $caKs, '-storetype', 'PKCS12',
    '-storepass', $pw, '-file', $pem) | Out-Null

$root = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $cer
Write-Ok "Root CA keystore : $caKs"
Write-Ok "For MDM (DER)    : $cer"
Write-Ok "For chain (PEM)  : $pem"
Write-Host "    Subject    : $($root.Subject)"
Write-Host "    Valid until: $($root.NotAfter)"
Write-Host "    SHA-1      : $($root.Thumbprint)   <- compare with what MDM / the iPad shows"
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host "  1. Deploy $([IO.Path]::GetFileName($cer)) to all EFB iPads with MDM (Certificate payload)."
Write-Host '  2. On the Gateway: 01-New-Csr.ps1, copy gateway.csr here, then run ca\11-Sign-GatewayCsr.ps1.'
Write-Warn2 'Back up this folder offline. Losing it means re-deploying a new root to every iPad.'
