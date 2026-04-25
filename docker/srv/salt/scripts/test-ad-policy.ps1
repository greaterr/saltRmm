Write-Host "=== AD/Domain Join Policy Check ==="

# 1. Check if domain join is blocked by policy
Write-Host "`n[1] Domain join restrictions..."
$key = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (Test-Path $key) {
    $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
    Write-Host "    BlockDomainJoin: $($props.BlockDomainJoin)"
    Write-Host "    All values:"
    $props | Format-List
} else {
    Write-Host "    (key not found - no restriction)"
}

# 2. Workstation service
Write-Host "`n[2] Workstation service (required for domain join)..."
Get-Service -Name LanmanWorkstation | Select-Object Name, Status, StartType | Format-Table

# 3. Net Logon service
Write-Host "`n[3] NetLogon service..."
Get-Service -Name Netlogon | Select-Object Name, Status, StartType | Format-Table

# 4. TCP/IP NetBIOS
Write-Host "`n[4] NetBIOS over TCP/IP..."
$adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
foreach ($a in $adapters) {
    Write-Host "    $($a.Description): TcpipNetbiosOptions=$($a.TcpipNetbiosOptions)"
}

# 5. Schannel / secure channel settings
Write-Host "`n[5] Schannel settings..."
$sch = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -ErrorAction SilentlyContinue
Write-Host "    RestrictAnonymous: $($sch.RestrictAnonymous)"
Write-Host "    RestrictAnonymousSAM: $($sch.RestrictAnonymousSAM)"
Write-Host "    LmCompatibilityLevel: $($sch.LmCompatibilityLevel)"
Write-Host "    NoLMHash: $($sch.NoLMHash)"

# 6. DNS devolution
Write-Host "`n[6] DNS settings..."
$dns = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -ErrorAction SilentlyContinue
Write-Host "    Policy DNS: $dns"

# 7. Check Windows Firewall - Domain profile
Write-Host "`n[7] Windows Firewall profiles..."
Get-NetFirewallProfile | Select-Object Name, Enabled | Format-Table

# 8. RPC services
Write-Host "`n[8] RPC services..."
@("RpcSs","RpcEptMapper","DcomLaunch") | ForEach-Object {
    $name = $_
    $svc = Get-Service $name -ErrorAction SilentlyContinue
    Write-Host "    ${name}: $($svc.Status)"
}

# 9. Test direct NetLogon RPC
Write-Host "`n[9] nltest DC discovery..."
$nl = & nltest /dsgetdc:rmm.lan /force 2>&1
Write-Host "    $nl"
