Write-Host "=== DNS Deep Test ==="

$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$Domain = "rmm.lan"

# Check what DNS server is actually being used
Write-Host "`n[1] Active DNS servers on all adapters..."
Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | Format-Table InterfaceAlias, ServerAddresses -AutoSize

# System resolver test (no explicit server)
Write-Host "`n[2] System resolver test..."
@("rmm.lan", "dc1.rmm.lan", "_ldap._tcp.dc._msdcs.rmm.lan", "_kerberos._tcp.dc._msdcs.rmm.lan") | ForEach-Object {
    $q = $_
    try {
        $r = Resolve-DnsName $q -ErrorAction Stop | Select-Object -First 1
        Write-Host "    [OK] $q -> $($r.IPAddress)$($r.NameTarget)"
    } catch {
        Write-Host "    [FAIL] $q -> $($_.Exception.Message)"
    }
}

# Check DNS multicast / mDNS interference
Write-Host "`n[3] DNS Client service..."
Get-Service -Name Dnscache | Select-Object Name, Status | Format-Table

# Check hosts file
Write-Host "`n[4] Relevant hosts entries..."
Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" | Where-Object { $_ -match "rmm" -or $_ -match $DC }

# Check EnableMulticast policy
Write-Host "`n[5] DNS Multicast policy..."
$mc = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -ErrorAction SilentlyContinue).EnableMulticast
Write-Host "    EnableMulticast: $mc (0=disabled, 1=enabled)"

# Try direct TCP connection to LDAP on DC
Write-Host "`n[6] Direct LDAP connection test..."
try {
    Add-Type -AssemblyName System.DirectoryServices.Protocols
    $id = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($DC, 389)
    $conn = New-Object System.DirectoryServices.Protocols.LdapConnection($id)
    $conn.AuthType = [System.DirectoryServices.Protocols.AuthType]::Anonymous
    $conn.Bind()
    Write-Host "    [OK] LDAP anonymous bind to $DC`:389 successful"
    $conn.Dispose()
} catch {
    Write-Host "    [FAIL] $($_.Exception.Message)"
}

# Check if DNS suffix is appended correctly
Write-Host "`n[7] Testing DNS with suffix..."
try {
    $r = Resolve-DnsName "dc1" -ErrorAction Stop | Select-Object -First 1
    Write-Host "    [OK] dc1 (no suffix) -> $($r.IPAddress)$($r.NameTarget)"
} catch {
    Write-Host "    [FAIL] dc1 (no suffix) -> $($_.Exception.Message)"
}
