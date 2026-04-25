#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Update DNS server address on Windows to match Salt Master/DC IP.
.DESCRIPTION
    Automatically updates DNS server to current DC IP and disables IPv6 DNS.
    Intended to be run manually or via Salt when network changes.
.EXAMPLE
    .\update-dns-client.ps1
    .\update-dns-client.ps1 -DnsServer 192.168.100.117
#>

param(
    [string]$DnsServer
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

Write-Step "Updating DNS configuration"

# Get current IP address if not specified
if (-not $DnsServer) {
    try {
        # Try to resolve Salt Master/DC
        $DnsServer = (Resolve-DnsName -Name "dc1.rmm.lan" -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Type -eq 'A' } | 
                      Select-Object -First 1).IPAddress
        if (-not $DnsServer) {
            $DnsServer = (Resolve-DnsName -Name "macbook-pro-timur.rmm.lan" -ErrorAction SilentlyContinue | 
                          Where-Object { $_.Type -eq 'A' } | 
                          Select-Object -First 1).IPAddress
        }
    } catch {
        Write-Fail "Could not resolve DC/Master DNS name"
        exit 1
    }
}

if (-not $DnsServer) {
    Write-Fail "No DNS server specified and could not resolve DC/Master"
    exit 1
}

Write-Info "Target DNS Server: $DnsServer"

# Get active network adapter
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceAlias -ne "Loopback" } | 
           Select-Object -First 1

if (-not $adapter) {
    Write-Fail "No active network adapter found"
    exit 1
}

$interfaceAlias = $adapter.InterfaceAlias
Write-Info "Interface: $interfaceAlias"

# Set DNS server (IPv4)
try {
    Set-DnsClientServerAddress -InterfaceAlias $interfaceAlias -ServerAddresses $DnsServer
    Write-OK "DNS server set to $DnsServer on $interfaceAlias"
} catch {
    Write-Fail "Failed to set DNS server: $_"
    exit 1
}

# Disable IPv6 DNS (optional, prevents IPv6 from taking precedence)
try {
    Disable-NetAdapterBinding -InterfaceAlias $interfaceAlias -ComponentID ms_tcpip6 -Confirm:$false
    Write-OK "IPv6 disabled on $interfaceAlias"
} catch {
    Write-Info "Could not disable IPv6 (may already be disabled): $_"
}

# Clear DNS cache
try {
    Clear-DnsClientCache
    Write-OK "DNS cache cleared"
} catch {
    Write-Fail "Failed to clear DNS cache: $_"
}

# Verify DNS resolution
Write-Step "Verifying DNS resolution"
try {
    $result = Resolve-DnsName -Name "dc1.rmm.lan" -ErrorAction Stop
    $resolvedIP = ($result | Where-Object { $_.Type -eq 'A' }).IPAddress
    Write-OK "dc1.rmm.lan resolves to $resolvedIP"
} catch {
    Write-Fail "DNS resolution failed: $_"
    exit 1
}

# Test AD connection
Write-Step "Testing AD connection"
try {
    $nltest = & nltest /dsgetdc:rmm.lan 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "AD connection successful"
    } else {
        Write-Fail "AD connection failed: $nltest"
    }
} catch {
    Write-Fail "AD connection test failed: $_"
}

Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host "Interface: $interfaceAlias" -ForegroundColor White
Write-Host "DNS Server: $DnsServer" -ForegroundColor White
Write-Host "IPv6: Disabled" -ForegroundColor White
