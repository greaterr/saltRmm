$Domain = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress

Write-Host "Fixing DNS policy..."

# Disable mDNS (it interferes with .lan domain resolution)
$dnsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
Set-ItemProperty -Path $dnsPolicy -Name "EnableMulticast" -Value 0 -Type DWord
Write-Host "[OK] mDNS disabled"

# Add domain search suffix
Set-ItemProperty -Path $dnsPolicy -Name "SearchList" -Value $Domain -Type String
Write-Host "[OK] Search list set to $Domain"

# Set primary DNS via registry directly (not just cmdlet)
$adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -and $_.IPAddress -notmatch "^169" }
foreach ($a in $adapters) {
    $result = $a.SetDNSServerSearchOrder(@($DC, "8.8.8.8"))
    Write-Host "[OK] DNS set on $($a.Description): $($result.ReturnValue)"
}

# Disable DNS devolution (prevents .lan -> . fallback)
Set-ItemProperty -Path $dnsPolicy -Name "UseDomainNameDevolution" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Restart DNS client
Restart-Service Dnscache -Force
Clear-DnsClientCache
ipconfig /flushdns | Out-Null
Start-Sleep -Seconds 3

Write-Host "`nVerifying SRV after fix..."
@("_ldap._tcp.dc._msdcs.$Domain", "_kerberos._tcp.dc._msdcs.$Domain") | ForEach-Object {
    $q = $_
    try {
        $r = Resolve-DnsName $q -Type SRV -ErrorAction Stop | Select-Object -First 1
        Write-Host "  [OK] $q -> $($r.NameTarget):$($r.Port)"
    } catch {
        Write-Host "  [FAIL] $q"
    }
}

Write-Host "`nnltest after fix..."
$nl = & nltest /dsgetdc:$Domain /force 2>&1
Write-Host ($nl -join "`n")
