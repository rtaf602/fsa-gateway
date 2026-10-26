<#
.SYNOPSIS
  Step 3 - Install the new keystore into Wildfly and point standalone.xml to it.
.DESCRIPTION
  - Backs up standalone.xml (standalone.xml.bak-<timestamp>)
  - Copies fsa-keystore-<stamp>.jks to [Wildfly]\standalone\configuration\
  - Updates gatewayKeyStore (file path + password) and gatewayKeyManager (password)
    as described in Installation Guide 11.4.3 (Figure 46)
  - Restarts the Wildfly service and waits for the HTTPS port
  The previous keystore file is left in place, so rollback is just restoring the backup
  (see 99-Rollback.ps1).
  Must be run as Administrator on the Gateway server.
.EXAMPLE
  .\scripts\03-Install-Keystore.ps1
.EXAMPLE
  .\scripts\03-Install-Keystore.ps1 -NoRestart
#>
[CmdletBinding()]
param(
    [string]$Stamp,
    [switch]$NoRestart
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-GatewayConfig
if (-not (Test-IsAdmin)) { throw 'Run this script in an elevated (Administrator) PowerShell.' }

$dir = Get-WorkDir -Config $cfg -Stamp $Stamp
$state = Get-State $dir
if (-not ($state.PSObject.Properties.Name -contains 'Imported')) { throw 'Certificate not imported yet. Run 02-Import-Certificate.ps1 first.' }

$confDir = Join-Path $cfg.WildflyPath 'standalone\configuration'
$xmlPath = Join-Path $confDir 'standalone.xml'
if (-not (Test-Path $xmlPath)) { throw "standalone.xml not found at $xmlPath (check WildflyPath in config.ps1)" }

$pw = Read-KeystorePassword
Write-Step 'Checking keystore password'
$leaf = Get-KeystoreLeafCert -Keystore $state.Keystore -Password $pw -WorkDir $dir
Write-Ok "Certificate $($leaf.Subject), valid until $($leaf.NotAfter)"
if ($leaf.NotAfter -lt (Get-Date)) { throw 'This certificate is already expired.' }

# 1. Backup
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$xmlPath.bak-$ts"
Copy-Item $xmlPath $backup
Write-Ok "Backup: $backup"

# 2. Copy keystore
$dest = Join-Path $confDir $state.KeystoreName
Copy-Item $state.Keystore $dest -Force
Write-Ok "Keystore copied: $dest"

# 3. Update standalone.xml
Write-Step 'Updating standalone.xml'
$doc = New-Object System.Xml.XmlDocument
$doc.PreserveWhitespace = $true
$doc.Load($xmlPath)

$ksNode = $doc.SelectSingleNode("//*[local-name()='key-store'][@name='gatewayKeyStore']")
if (-not $ksNode) { throw "key-store 'gatewayKeyStore' not found in standalone.xml" }
$ksCred = $ksNode.SelectSingleNode("*[local-name()='credential-reference']")
$ksFile = $ksNode.SelectSingleNode("*[local-name()='file']")
$kmNodes = $doc.SelectNodes("//*[local-name()='key-manager'][@key-store='gatewayKeyStore']")
if (-not $ksCred -or -not $ksFile) { throw 'gatewayKeyStore is missing credential-reference or file element.' }
if ($kmNodes.Count -lt 1) { throw "key-manager for 'gatewayKeyStore' not found in standalone.xml" }

$oldFile = $ksFile.GetAttribute('path')

# Edit only the three values in the raw text so the rest of the file stays byte-identical.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$raw = [IO.File]::ReadAllText($xmlPath, $utf8)
$newPw = $pw; $newFile = $state.KeystoreName
$setCred = { param($block) [regex]::Replace($block, '(<credential-reference\b[^>]*\bclear-text=)(["''])[^"'']*\2', { param($m) $m.Groups[1].Value + '"' + $newPw + '"' }) }
$opts = [Text.RegularExpressions.RegexOptions]::Singleline

$raw = [regex]::Replace($raw, '<key-store\b[^>]*\bname=["'']gatewayKeyStore["''][^>]*>.*?</key-store>', {
    param($m)
    $b = & $setCred $m.Value
    [regex]::Replace($b, '(<file\b[^>]*\bpath=)(["''])[^"'']*\2', { param($f) $f.Groups[1].Value + '"' + $newFile + '"' })
}, $opts)
$raw = [regex]::Replace($raw, '<key-manager\b[^>]*\bkey-store=["'']gatewayKeyStore["''][^>]*>.*?</key-manager>', {
    param($m) & $setCred $m.Value
}, $opts)

# Verify the result before writing it
$check = New-Object System.Xml.XmlDocument
$check.LoadXml($raw)
$cks = $check.SelectSingleNode("//*[local-name()='key-store'][@name='gatewayKeyStore']")
$okKs = ($cks.SelectSingleNode("*[local-name()='credential-reference']").GetAttribute('clear-text') -eq $pw) -and
        ($cks.SelectSingleNode("*[local-name()='file']").GetAttribute('path') -eq $state.KeystoreName)
$okKm = $true
foreach ($km in $check.SelectNodes("//*[local-name()='key-manager'][@key-store='gatewayKeyStore']")) {
    $c = $km.SelectSingleNode("*[local-name()='credential-reference']")
    if (-not $c -or $c.GetAttribute('clear-text') -ne $pw) { $okKm = $false }
}
if (-not ($okKs -and $okKm)) { throw 'Could not update standalone.xml safely - file left unchanged. Edit it manually (Installation Guide 11.4.3).' }

[IO.File]::WriteAllText($xmlPath, $raw, $utf8)
Write-Ok "gatewayKeyStore path: $oldFile -> $($state.KeystoreName); passwords updated ($($kmNodes.Count) key-manager)"

# 4. Restart
if ($NoRestart) {
    Write-Warn2 "Restart the '$($cfg.WildflyServiceName)' service manually to apply the change."
} else {
    Write-Step "Restarting service '$($cfg.WildflyServiceName)'"
    Restart-Service -Name $cfg.WildflyServiceName -Force
    Write-Step "Waiting for HTTPS port $($cfg.HttpsPort) (up to 5 minutes)"
    $deadline = (Get-Date).AddMinutes(5); $up = $false
    while ((Get-Date) -lt $deadline -and -not $up) {
        Start-Sleep -Seconds 5
        try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', [int]$cfg.HttpsPort); $up = $c.Connected; $c.Close() } catch { }
    }
    if ($up) { Write-Ok 'Wildfly is listening.' }
    else { Write-Warn2 "Port not open yet. Check [Wildfly]\standalone\log\server.log. Rollback: .\scripts\99-Rollback.ps1 -Backup '$backup'" }
}

$state | Add-Member -NotePropertyName Installed -NotePropertyValue (Get-Date).ToString('s') -Force
$state | Add-Member -NotePropertyName Backup -NotePropertyValue $backup -Force
$state | ConvertTo-Json | Set-Content -Path (Join-Path $dir 'state.json') -Encoding UTF8

Write-Host ''
Write-Host 'Next: .\scripts\04-Test-Gateway.ps1  (then test sync from an iPad with a Test user)' -ForegroundColor Cyan
Write-Host "Rollback if needed: .\scripts\99-Rollback.ps1 -Backup '$backup'" -ForegroundColor DarkGray
