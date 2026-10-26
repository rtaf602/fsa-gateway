# Shared helpers for the Flysmart+ Gateway SSL scripts.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Alias = 'mach9'   # mandatory alias required by NAVBLUE

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn2([string]$Message){ Write-Host "[WARN] $Message" -ForegroundColor Yellow }

function Get-GatewayConfig {
    $path = Join-Path $script:RepoRoot 'config.ps1'
    if (-not (Test-Path $path)) {
        throw "config.ps1 not found. Copy config.example.ps1 to config.ps1 and edit it."
    }
    . $path
    if (-not $Config.Domain) { throw "Domain is empty in config.ps1" }
    if ($Config.Domain -match '^\d+\.\d+\.\d+\.\d+$') { throw "Domain must be a DNS name, not an IP address." }
    return $Config
}

function Get-Keytool {
    if ($env:JAVA_HOME) {
        foreach ($name in 'keytool.exe', 'keytool') {
            $p = Join-Path (Join-Path $env:JAVA_HOME 'bin') $name
            if (Test-Path $p) { return $p }
        }
    }
    $cmd = Get-Command keytool -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "keytool not found. Set JAVA_HOME to the JDK used by the Gateway (see Installation Guide 5.1.2)."
}

function Invoke-Keytool {
    param([string[]]$Arguments, [switch]$Quiet, [switch]$Interactive)
    $kt = Get-Keytool
    # Force English output so it can be parsed
    $all = @('-J-Duser.language=en', '-J-Duser.country=US') + $Arguments
    if ($Interactive) {
        # Output goes straight to the console so the user can answer keytool prompts
        & $kt @all
        if ($LASTEXITCODE -ne 0) { throw "keytool failed (exit $LASTEXITCODE)" }
        return
    }
    $out = & $kt @all 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $safe = (($out | Where-Object { $_ -notmatch '^Picked up' }) -join "`n")
        throw "keytool failed (exit $code):`n$safe"
    }
    if (-not $Quiet) { $out | Where-Object { $_ -and $_ -notmatch '^Picked up' } | ForEach-Object { Write-Host "    $_" } }
    return ,$out
}

function Test-PasswordAllowed([string]$Plain) {
    if ($Plain.Length -lt 8) { return 'Password must be at least 8 characters.' }
    # Characters that break the installer / standalone.xml (Release Note 5.6.1 known issue)
    if ($Plain -match '[<>"=/#:&''\\\s]') {
        return 'Password must not contain < > " = / # : & '' \ or spaces.'
    }
    return $null
}

function ConvertFrom-Secure([Security.SecureString]$Secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Read-KeystorePassword {
    param([switch]$Confirm)
    if ($env:FSA_KEYSTORE_PASSWORD) { return $env:FSA_KEYSTORE_PASSWORD }  # for unattended testing only
    while ($true) {
        $p1 = ConvertFrom-Secure (Read-Host -AsSecureString 'Keystore password')
        $err = Test-PasswordAllowed $p1
        if ($err) { Write-Warn2 $err; continue }
        if ($Confirm) {
            $p2 = ConvertFrom-Secure (Read-Host -AsSecureString 'Confirm password')
            if ($p1 -ne $p2) { Write-Warn2 'Passwords do not match.'; continue }
        }
        return $p1
    }
}

function Get-WorkDir {
    param($Config, [string]$Stamp)
    if (-not $Stamp) {
        if (-not (Test-Path $Config.WorkRoot)) { throw "WorkRoot $($Config.WorkRoot) not found. Run 01-New-Csr.ps1 first." }
        $latest = Get-ChildItem $Config.WorkRoot -Directory | Where-Object { $_.Name -match '^\d{8}(-\d+)?$' } |
                  Sort-Object Name | Select-Object -Last 1
        if (-not $latest) { throw "No work folder found in $($Config.WorkRoot). Run 01-New-Csr.ps1 first." }
        return $latest.FullName
    }
    $d = Join-Path $Config.WorkRoot $Stamp
    if (-not (Test-Path $d)) { throw "Work folder $d not found." }
    return $d
}

function Get-State([string]$WorkDir) {
    $f = Join-Path $WorkDir 'state.json'
    if (-not (Test-Path $f)) { throw "state.json not found in $WorkDir" }
    return Get-Content $f -Raw | ConvertFrom-Json
}

function Get-KeystoreLeafCert {
    param([string]$Keystore, [string]$Password, [string]$WorkDir)
    $tmp = Join-Path $WorkDir 'leaf-export.pem'
    Invoke-Keytool -Quiet -Arguments @('-exportcert', '-rfc', '-alias', $script:Alias, '-keystore', $Keystore,
        '-storetype', 'PKCS12', '-storepass', $Password, '-file', $tmp) | Out-Null
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $tmp
    Remove-Item $tmp -Force
    return $cert
}

function Get-SanDnsNames($Cert) {
    $ext = $Cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' }
    if (-not $ext) { return @() }
    $text = $ext.Format($true)
    return @([regex]::Matches($text, '(?:DNS Name|DNS)[=:]\s*([^\s,]+)') | ForEach-Object { $_.Groups[1].Value })
}

function Test-IsAdmin {
    $onWindows = ($PSVersionTable.PSVersion.Major -le 5) -or $IsWindows
    if (-not $onWindows) { return $true }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
