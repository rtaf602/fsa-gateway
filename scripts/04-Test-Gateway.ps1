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
.PARAMETER CaFile
  Root CA certificate (.cer/.pem) to trust for this test - use it with the private CA
  (option A) when the root is not installed in the Windows certificate store.
.EXAMPLE
  .\scripts\04-Test-Gateway.ps1 -Server 127.0.0.1
.EXAMPLE
  .\scripts\04-Test-Gateway.ps1 -Server 127.0.0.1 -CaFile C:\Airbus\rtaf602-efb-root-ca.pem
#>
[CmdletBinding()]
param(
    [string]$Server,
    [int]$Port,
    [int]$WarnDays,
    [string]$CaFile
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

$errors = $script:policyErrors
if ($CaFile -and ($errors -band [System.Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors)) {
    # Validate the chain against the given private root instead of the OS store
    $root = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (Resolve-Path $CaFile).Path
    $ch = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    $ch.ChainPolicy.RevocationMode = 'NoCheck'
    $ch.ChainPolicy.VerificationFlags = 'AllowUnknownCertificateAuthority'
    [void]$ch.ChainPolicy.ExtraStore.Add($root)
    $built = $ch.Build($remote)
    $top = $ch.ChainElements[$ch.ChainElements.Count - 1].Certificate
    $other = @($ch.ChainStatus | Where-Object { $_.Status -ne 'UntrustedRoot' -and $_.Status -ne 'NoError' })
    if ($built -and $top.Thumbprint -eq $root.Thumbprint -and $other.Count -eq 0) {
        $errors = $errors -bxor [System.Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors
        Write-Ok "Chain verified against private root $($root.Subject)"
    } else {
        $script:chainStatus = @($ch.ChainStatus | ForEach-Object { "$($_.Status): $($_.StatusInformation.Trim())" }) + "top of chain: $($top.Subject)"
    }
}

# iOS requirements for TLS server certificates
$lifetime = ($remote.NotAfter - $remote.NotBefore).TotalDays
$eku = $remote.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' }
$iosIssues = @()
if ($lifetime -gt 825) { $iosIssues += "lifetime $([int]$lifetime) days > 825 (iOS will reject it)" }
if (-not $eku -or $eku.Format($false) -notmatch 'Server Authentication|1\.3\.6\.1\.5\.5\.7\.3\.1') { $iosIssues += 'EKU serverAuth missing (required by iOS)' }
$bits = 0
try {
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($remote)
    if ($rsa) { $bits = $rsa.ExportParameters($false).Modulus.Length * 8 }
} catch { }
if ($bits -gt 0 -and $bits -lt 2048) { $iosIssues += "RSA key $bits bits < 2048" }

$code = 0
if ($iosIssues) {
    $iosIssues | ForEach-Object { Write-Host "[FAIL] iOS: $_" -ForegroundColor Red }
    $code = 2
} elseif ($errors -ne [System.Net.Security.SslPolicyErrors]::None) {
    $script:policyErrors = $errors
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
