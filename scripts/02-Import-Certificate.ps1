<#
.SYNOPSIS
  Step 2 - Import the certificate issued by the CA into the keystore created in step 1.
.PARAMETER CertFile
  The certificate for the domain (.crt / .cer / .pem), or a .p7b containing the full chain.
.PARAMETER ChainFile
  The intermediate bundle from the CA (.ca-bundle / .crt). Optional when CertFile is a .p7b
  or already contains the full chain.
.PARAMETER Stamp
  Work folder name (yyyyMMdd). Defaults to the most recent one.
.EXAMPLE
  .\scripts\02-Import-Certificate.ps1 -CertFile .\efb-gateway_rtaf602_com.crt -ChainFile .\efb-gateway_rtaf602_com.ca-bundle
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CertFile,
    [string]$ChainFile,
    [string]$Stamp
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-GatewayConfig
$dir = Get-WorkDir -Config $cfg -Stamp $Stamp
$state = Get-State $dir
$ks = $state.Keystore

$CertFile = (Resolve-Path $CertFile).Path
Write-Step "Keystore : $ks"

# Build the reply file (leaf first, then intermediates). Make sure every PEM block
# ends with a newline - a plain "copy /b" can glue END/BEGIN lines together.
$reply = Join-Path $dir 'fullchain.pem'
if ($CertFile -match '\.p7[bc]$' -and -not $ChainFile) {
    Copy-Item $CertFile $reply -Force
} else {
    $parts = @((Get-Content $CertFile -Raw).Trim())
    if ($ChainFile) { $parts += (Get-Content (Resolve-Path $ChainFile).Path -Raw).Trim() }
    $text = ($parts -join "`n") + "`n"
    if ($text -notmatch '-----BEGIN CERTIFICATE-----') { throw "CertFile is not a PEM certificate. Convert DER files first or use the .p7b." }
    [IO.File]::WriteAllText($reply, ($text -replace "`r`n", "`n"))
}

$pw = Read-KeystorePassword

Write-Step 'Importing certificate reply into alias mach9'
Write-Host '    (if keytool asks "Trust this certificate?", check the issuer and answer yes)' -ForegroundColor DarkGray
Invoke-Keytool -Interactive -Arguments @('-importcert', '-alias', $script:Alias, '-trustcacerts', '-file', $reply,
    '-keystore', $ks, '-storetype', 'PKCS12', '-storepass', $pw) | Out-Null

Write-Step 'Verifying keystore'
$list = (Invoke-Keytool -Quiet -Arguments @('-list', '-v', '-alias', $script:Alias, '-keystore', $ks,
    '-storetype', 'PKCS12', '-storepass', $pw)) -join "`n"

$problems = @()
if ($list -notmatch 'Entry type:\s*PrivateKeyEntry') { $problems += 'alias mach9 is not a PrivateKeyEntry' }
$chainLen = 0
if ($list -match 'Certificate chain length:\s*(\d+)') { $chainLen = [int]$Matches[1] }
if ($chainLen -lt 2) { $problems += "certificate chain length is $chainLen (intermediate missing - iPads will reject it)" }

$leaf = Get-KeystoreLeafCert -Keystore $ks -Password $pw -WorkDir $dir
$san = Get-SanDnsNames $leaf
if ($san -notcontains $state.Domain) { $problems += "SAN does not contain $($state.Domain) (found: $($san -join ', '))" }
if ($leaf.Issuer -eq $leaf.Subject) { $problems += 'certificate is still self-signed - import did not replace it' }

Write-Host "    Subject   : $($leaf.Subject)"
Write-Host "    Issuer    : $($leaf.Issuer)"
Write-Host "    SAN       : $($san -join ', ')"
Write-Host "    Valid     : $($leaf.NotBefore) -> $($leaf.NotAfter)"
Write-Host "    Chain len : $chainLen"

if ($problems) {
    $problems | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    throw 'Keystore verification failed.'
}

$state | Add-Member -NotePropertyName Imported -NotePropertyValue (Get-Date).ToString('s') -Force
$state | Add-Member -NotePropertyName NotAfter -NotePropertyValue $leaf.NotAfter.ToString('s') -Force
$state | ConvertTo-Json | Set-Content -Path (Join-Path $dir 'state.json') -Encoding UTF8

Write-Ok 'Keystore is ready. Next: run 03-Install-Keystore.ps1 as Administrator.'
