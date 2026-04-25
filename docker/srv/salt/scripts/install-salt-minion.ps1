#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs or reconfigures Salt Minion on Windows.
.DESCRIPTION
    Downloads and installs Salt Minion if not present,
    or reconfigures existing installation to use the correct master.
    Idempotent - safe to run multiple times.
.PARAMETER Master
    Salt master hostname (default: macbook-pro-timur.rmm.lan)
.PARAMETER MinionId
    Minion ID (default: $env:COMPUTERNAME)
.PARAMETER Version
    Salt version to install (default: 3006.23)
.EXAMPLE
    .\install-salt-minion.ps1
    .\install-salt-minion.ps1 -Master dc1.rmm.lan -MinionId NOTEBOOK_VN
#>
param(
    [string]$Master   = "macbook-pro-timur.rmm.lan",
    [string]$MinionId = $env:COMPUTERNAME,
    [string]$Version  = "3006.23"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Msg)
    Write-Host "`n[*] $Msg" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Msg)
    Write-Host "    [OK] $Msg" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Msg)
    Write-Host "    [FAIL] $Msg" -ForegroundColor Red
}

function Write-Info {
    param([string]$Msg)
    Write-Host "    [--] $Msg" -ForegroundColor Gray
}

$MinionConfDir = "$env:ProgramData\Salt Project\Salt\conf"
$MinionConfFile = "$MinionConfDir\minion"
$ServiceName = "salt-minion"

# ─────────────────────────────────────────
# 0. Pre-flight check
# ─────────────────────────────────────────
Write-Step "Pre-flight check"
Write-Info "Hostname       : $env:COMPUTERNAME"
Write-Info "Target Master  : $Master"
Write-Info "Minion ID      : $MinionId"
Write-Info "Salt Version   : $Version"

# ─────────────────────────────────────────
# 1. Check if Salt is already installed
# ─────────────────────────────────────────
Write-Step "Checking Salt Minion installation"

$saltExe = "$env:ProgramFiles\Salt Project\Salt\salt-minion.exe"
$saltInstalled = Test-Path $saltExe

if ($saltInstalled) {
    Write-OK "Salt Minion is installed at: $saltExe"
    try {
        $currentVersion = & $saltExe --version 2>$null
        Write-Info "Current version: $currentVersion"
    } catch {
        Write-Info "Could not determine version"
    }
} else {
    Write-Info "Salt Minion not found, will install"
}

# ─────────────────────────────────────────
# 2. Check master connectivity
# ─────────────────────────────────────────
Write-Step "Testing connectivity to Salt Master"
try {
    $masterIP = [System.Net.Dns]::GetHostAddresses($Master) | 
                Where-Object { $_.AddressFamily -eq 'InterNetwork' } | 
                Select-Object -First 1
    if ($masterIP) {
        Write-OK "Master $Master resolves to $($masterIP.IPAddressToString)"
        
        # Test ports 4505 and 4506
        $port4505 = Test-NetConnection -ComputerName $Master -Port 4505 -WarningAction SilentlyContinue -InformationLevel Quiet
        $port4506 = Test-NetConnection -ComputerName $Master -Port 4506 -WarningAction SilentlyContinue -InformationLevel Quiet
        
        if ($port4505) { Write-OK "Port 4505 (publish_port) is reachable" } 
        else { Write-Fail "Port 4505 is not reachable" }
        
        if ($port4506) { Write-OK "Port 4506 (ret_port) is reachable" } 
        else { Write-Fail "Port 4506 is not reachable" }
    } else {
        Write-Fail "Could not resolve $Master"
        exit 1
    }
} catch {
    Write-Fail "DNS resolution failed for $Master : $_"
    exit 1
}

# ─────────────────────────────────────────
# 3. Install Salt if not present
# ─────────────────────────────────────────
if (-not $saltInstalled) {
    Write-Step "Downloading Salt Minion $Version"
    
    $msiPath = "$env:TEMP\Salt-Minion-$Version.msi"
    
    # Multiple fallback URLs (Salt Project moved to Broadcom)
    $urls = @(
        "https://packages.broadcom.com/artifactory/saltproject-generic/windows/$Version/Salt-Minion-$Version-Py3-AMD64.msi",
        "https://github.com/saltstack/salt/releases/download/v$Version/Salt-Minion-$Version-Py3-AMD64.msi"
    )
    
    $downloaded = $false
    foreach ($url in $urls) {
        try {
            Write-Info "Trying: $url"
            Invoke-WebRequest -Uri $url -OutFile $msiPath -UseBasicParsing -TimeoutSec 60
            Write-OK "Downloaded to: $msiPath"
            $downloaded = $true
            break
        } catch {
            Write-Info "  Failed: $_"
            continue
        }
    }
    
    if (-not $downloaded) {
        Write-Fail "All download sources failed. Check internet connectivity or download manually."
        exit 1
    }
        
    Write-Step "Installing Salt Minion"
    $msiArgs = @(
        "/i", "`"$msiPath`"",
        "/qn",
        "MASTER=$Master",
        "MINION_ID=$MinionId"
    )
    $proc = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
        Write-OK "Installation completed (exit code: $($proc.ExitCode))"
    } else {
        Write-Fail "Installation failed with exit code: $($proc.ExitCode)"
        exit 1
    }
    
    Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────
# 4. Configure / Update minion config
# ─────────────────────────────────────────
Write-Step "Configuring minion"

# Ensure config directory exists
if (-not (Test-Path $MinionConfDir)) {
    New-Item -ItemType Directory -Path $MinionConfDir -Force | Out-Null
    Write-OK "Created config directory: $MinionConfDir"
}

# Read existing config or create new
$existingConfig = @{}
if (Test-Path $MinionConfFile) {
    Write-Info "Reading existing config: $MinionConfFile"
    Get-Content $MinionConfFile | ForEach-Object {
        if ($_ -match '^([a-z_]+):\s*(.+)$') {
            $existingConfig[$matches[1]] = $matches[2] -replace '^["'']|["'']$'
        }
    }
}

# Build new config
$newConfig = @"
# Salt Minion Configuration
# Generated by install-salt-minion.ps1 on $(Get-Date)

master: $Master
id: $MinionId

# Reconnection settings
acceptance_wait_time: 10
acceptance_wait_time_max: 300
rejected_retry: True
random_reauth_delay: 60

# Logging
log_level: info
log_file: C:\ProgramData\Salt Project\Salt\var\log\salt\minion

# Grains
grains:
  domain_joined: True
  ad_domain: rmm.lan
"@

# Write config
Set-Content -Path $MinionConfFile -Value $newConfig -Encoding UTF8
Write-OK "Wrote config to: $MinionConfFile"
Write-Info "  master: $Master"
Write-Info "  id: $MinionId"

# ─────────────────────────────────────────
# 5. Start/Restart service
# ─────────────────────────────────────────
Write-Step "Managing Salt Minion service"

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Info "Service exists, current status: $($service.Status)"
    if ($service.Status -eq 'Running') {
        Write-Info "Restarting service..."
        Restart-Service -Name $ServiceName -Force
        Write-OK "Service restarted"
    } else {
        Write-Info "Starting service..."
        Start-Service -Name $ServiceName
        Write-OK "Service started"
    }
} else {
    Write-Info "Service not found, waiting for it to appear..."
    Start-Sleep -Seconds 5
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Start-Service -Name $ServiceName
        Write-OK "Service started"
    } else {
        Write-Fail "Service still not found after waiting"
    }
}

# ─────────────────────────────────────────
# 6. Verify
# ─────────────────────────────────────────
Write-Step "Verifying installation"
Start-Sleep -Seconds 3

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Write-OK "Service is running"
} else {
    Write-Fail "Service is not running"
}

# Check if master is reachable via test.ping
# This requires key to be accepted on master side
Write-Info "Note: Key acceptance required on master side"
Write-Info "Run on master: docker exec salt-master salt-key -a $MinionId"

Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host "Minion ID: $MinionId" -ForegroundColor White
Write-Host "Master:    $Master" -ForegroundColor White
Write-Host "Service:   $($service.Status)" -ForegroundColor White
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Accept key on master: docker exec salt-master salt-key -a $MinionId"
Write-Host "2. Test connection:       docker exec salt-master salt '$MinionId' test.ping"
