#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Joins a Windows machine to rmm.lan Samba AD domain.
.DESCRIPTION
    1. Configures DNS to point at the DC
    2. Verifies network connectivity to DC ports
    3. Verifies DNS resolution
    4. Joins the domain
    5. Schedules reboot (or reboots immediately)
.PARAMETER DCAddress
    IP address of the Domain Controller (default: dc1.rmm.lan)
.PARAMETER Domain
    Domain FQDN (default: rmm.lan)
.PARAMETER DomainUser
    Domain administrator username (default: Administrator)
.PARAMETER DomainPass
    Domain administrator password (default: Admin1234!)
.PARAMETER NoReboot
    If set, machine will NOT reboot automatically after joining
.EXAMPLE
    .\join-domain.ps1
    .\join-domain.ps1 -DCAddress 10.0.0.5 -NoReboot
#>
param(
    [string]$DCAddress  = "macbook-pro-timur.rmm.lan",
    [string]$Domain     = "rmm.lan",
    [string]$DomainUser = "Administrator",
    [string]$DomainPass = "Admin1234!",
    [switch]$NoReboot
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

# ─────────────────────────────────────────
# 0. Pre-flight info
# ─────────────────────────────────────────
Write-Step "Pre-flight check"
Write-Info "Hostname       : $env:COMPUTERNAME"
Write-Info "Current domain : $env:USERDOMAIN"
Write-Info "Target DC      : $DCAddress"
Write-Info "Target domain  : $Domain"

$currentDomain = (Get-WmiObject Win32_ComputerSystem).Domain
if ($currentDomain -ieq $Domain) {
    Write-Fail "Already joined to $Domain. Exiting."
    exit 0
}

# ─────────────────────────────────────────
# 1. Set DNS
# ─────────────────────────────────────────
Write-Step "Configuring DNS -> $DCAddress"
try {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false }
    if (-not $adapters) {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    }
    foreach ($adapter in $adapters) {
        # Сначала резолвим DCAddress через текущий DNS или mDNS
        try {
            $DCIPResolved = ([System.Net.Dns]::GetHostAddresses($DCAddress) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1).IPAddressToString
        } catch {
            # Fallback на прямой IP если mDNS не работает
            $DCIPResolved = $DCAddress
        }
        Write-Info "DC $DCAddress resolved to: $DCIPResolved"
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses @($DCIPResolved, "8.8.8.8")
        Write-OK "DNS set on adapter: $($adapter.Name) ($($adapter.InterfaceDescription))"
    }
} catch {
    Write-Fail "Failed to set DNS: $_"
    exit 1
}

Start-Sleep -Seconds 2

# ─────────────────────────────────────────
# 2. Test port connectivity
# ─────────────────────────────────────────
Write-Step "Testing connectivity to DC $DCAddress"
$ports = @(
    @{ Port = 53;  Name = "DNS" },
    @{ Port = 88;  Name = "Kerberos" },
    @{ Port = 135; Name = "RPC" },
    @{ Port = 389; Name = "LDAP" },
    @{ Port = 445; Name = "SMB" },
    @{ Port = 636; Name = "LDAPS" }
)

$allOk = $true
foreach ($p in $ports) {
    $result = Test-NetConnection -ComputerName $DCAddress -Port $p.Port -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($result) {
        Write-OK "Port $($p.Port) ($($p.Name))"
    } else {
        Write-Fail "Port $($p.Port) ($($p.Name)) - unreachable"
        $allOk = $false
    }
}

if (-not $allOk) {
    Write-Host "`n[!] Some ports are unreachable. Domain join may fail." -ForegroundColor Yellow
}

# ─────────────────────────────────────────
# 3. Test DNS resolution
# ─────────────────────────────────────────
Write-Step "Testing DNS resolution for $Domain"
try {
    $dns = Resolve-DnsName $Domain -Server $DCIPResolved -ErrorAction Stop
    $resolvedIP = ($dns | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
    Write-OK "$Domain resolves to $resolvedIP"
} catch {
    Write-Fail "Cannot resolve $Domain via $DCAddress"
    Write-Info "Error: $_"
    exit 1
}

# ─────────────────────────────────────────
# 4. Test DC reachability via nltest
# ─────────────────────────────────────────
Write-Step "Testing DC reachability"
try {
    $nltest = & nltest /dsgetdc:$Domain /force 2>&1
    if ($LASTEXITCODE -eq 0) {
        $dcLine = $nltest | Where-Object { $_ -match "DC:" -or $_ -match "\\\\" } | Select-Object -First 1
        Write-OK "DC found: $($dcLine.Trim())"
    } else {
        Write-Info "nltest result: $nltest"
        Write-Info "Proceeding with domain join anyway..."
    }
} catch {
    Write-Info "nltest not available, skipping DC check"
}

# ─────────────────────────────────────────
# 5. Join domain
# ─────────────────────────────────────────
Write-Step "Joining domain $Domain"
try {
    $securePass = ConvertTo-SecureString $DomainPass -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential("$DomainUser@$Domain", $securePass)

    if ($NoReboot) {
        Add-Computer -DomainName $Domain -Credential $cred -Force
        Write-OK "Joined domain $Domain successfully"
        Write-Host "`n[!] NoReboot flag set — please reboot manually to complete domain join." -ForegroundColor Yellow
    } else {
        Write-Info "Joining and rebooting in 10 seconds..."
        Add-Computer -DomainName $Domain -Credential $cred -Force -Restart -RestartTimeoutSec 10
        Write-OK "Joined domain $Domain — rebooting..."
    }
} catch {
    Write-Fail "Domain join failed: $_"
    exit 1
}
