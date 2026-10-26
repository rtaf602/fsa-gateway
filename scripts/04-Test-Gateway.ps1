<#
.SYNOPSIS
  Step 4 - Check the certificate the Gateway actually serves, the way a client (iPad) sees it.
.DESCRIPTION
  Connects with TLS to <Domain>:<HttpsPort>, validates the chain and host name, and reports
  days until expiry. Exit code: 0 = OK, 1 = warning (expires soon), 2 = error.
  Can be scheduled daily with Task Scheduler to get an early expiry alert.
.PARAMETER Server
  Connect to this host/IP instead of the domain (the domain is still used for SNI and
  name validation). Useful on the server itself: -Server 127.0.0.1
.EXAMPLE
  .\scripts\04-Test-Gateway.ps1
.EXAMPLE
  .\scripts\04-Test-Gateway.ps1 -Server 127.0.0.1
#>
[CmdletBinding()]
param(
    [string]$Server,
    [int]$Port,
    [int]$WarnDays
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-GatewayConfig
$domain = $cfg.Domain
if (-not $Server) { $Server = $domain }
if (-not $Port) { $Port = [int]$cfg.HttpsPort }
if (-not $WarnDays) { $WarnDays = [int]$cfg.WarnDays }

Write-Step "Connecting to $Server`:$Port (SNI/host name: $domain)"
$script:policyErrors = $null
$script:chainSubjects = @()
$script:chainStatus = @()
$callback = [System.Net.Security.RemoteCertificateValidationCallback] {
    param($s, $cert, $chain, $errors)
    $script:policyErrors = $errors
    $script:chainSubjects = @($chain.ChainElements | ForEach-Object { $_.Certificate.Subject })
    $script:chainStatus = @($chain.ChainStatus | ForEach-Object { "$($_.Status): $($_.StatusInformation.Trim())" })
    return $true
}

$tcp = New-Object Net.Sockets.TcpClient
try {
    $tcp.Connect($Server, $Port)
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $callback)
    $ssl.AuthenticateAsClient($domain)
    $remote = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $ssl.RemoteCertificate
    $proto = $ssl.SslProtocol
    $ssl.Dispose()
} catch {
    Write-Host "[FAIL] TLS connection failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
} finally { $tcp.Close() }

$san = Get-SanDnsNames $remote
$days = [int][Math]::Floor(($remote.NotAfter - (Get-Date)).TotalDays)

Write-Host "    Protocol  : $proto"
Write-Host "    Subject   : $($remote.Subject)"
Write-Host "    Issuer    : $($remote.Issuer)"
Write-Host "    SAN       : $($san -join ', ')"
Write-Host "    Expires   : $($remote.NotAfter)  ($days days left)"
Write-Host '    Chain     :'
foreach ($sub in $script:chainSubjects) { Write-Host "      - $sub" }

$code = 0
if ($script:policyErrors -ne [System.Net.Security.SslPolicyErrors]::None) {
    Write-Host "[FAIL] Validation errors: $($script:policyErrors)" -ForegroundColor Red
    foreach ($st in $script:chainStatus) { Write-Host "       $st" -ForegroundColor Red }
    Write-Host '       RemoteCertificateNameMismatch -> certificate does not cover the domain'
    Write-Host '       RemoteCertificateChainErrors  -> self-signed or intermediate missing'
    $code = 2
} elseif ($days -lt $WarnDays) {
    Write-Warn2 "Certificate expires in $days days - start the renewal (01-New-Csr.ps1)."
    $code = 1
} else {
    Write-Ok 'Certificate is valid and trusted.'
}
if ($code -eq 0) { Write-Host "Open https://$domain`:$Port/fsa-gateway and test sync from an iPad." -ForegroundColor Cyan }
exit $code
