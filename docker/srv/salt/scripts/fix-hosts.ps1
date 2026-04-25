$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$Domain = "rmm.lan"
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

$entries = @(
    "$DC dc1.$Domain",
    "$DC $Domain",
    "$DC _msdcs.$Domain",
    "$DC gc._msdcs.$Domain",
    "$DC DC1._msdcs.$Domain"
)

$hostsContent = Get-Content $hostsPath -Raw

foreach ($entry in $entries) {
    $host = ($entry -split "\s+")[1]
    if ($hostsContent -notmatch [regex]::Escape($host)) {
        Add-Content -Path $hostsPath -Value $entry
        Write-Host "[OK] Added: $entry"
    } else {
        Write-Host "[--] Exists: $entry"
    }
}

# Most important - register SRV records via DNS client directly
# Force Windows to use TCP for all DNS (avoids UDP issues)
Write-Host "`nForcing DNS over TCP..."
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "MaxNegativeCacheTtl" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "NegativeCacheTime" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Restart DNS client to clear negative cache
Restart-Service Dnscache -Force -ErrorAction SilentlyContinue
Write-Host "[OK] DNS cache cleared and service restarted"

Start-Sleep -Seconds 2

# Verify SRV records now
Write-Host "`nVerifying SRV records..."
@("_ldap._tcp.dc._msdcs.$Domain", "_kerberos._tcp.dc._msdcs.$Domain") | ForEach-Object {
    $q = $_
    try {
        $r = Resolve-DnsName $q -Type SRV -ErrorAction Stop | Select-Object -First 1
        Write-Host "    [OK] $q -> $($r.NameTarget):$($r.Port)"
    } catch {
        Write-Host "    [FAIL] $q"
    }
}

# Now try nltest
Write-Host "`nTrying nltest..."
$nl = & nltest /dsgetdc:$Domain /force 2>&1
Write-Host $nl
