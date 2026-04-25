Write-Host "=== DNS Config ==="
$adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
foreach ($a in $adapters) {
    Write-Host "Adapter: $($a.Description)"
    Write-Host "  IP: $($a.IPAddress -join ', ')"
    Write-Host "  DNS: $($a.DNSServerSearchOrder -join ', ')"
    Write-Host "  Domain: $($a.DNSDomain)"
}

Write-Host "`n=== DNS Resolution ==="
foreach ($name in @("dc1.rmm.lan", "rmm.lan", "macbook-pro-timur.rmm.lan")) {
    $r = Resolve-DnsName $name -Type A -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq "A" } | Select-Object -First 1
    if ($r) { Write-Host "  $name -> $($r.IPAddress)" }
    else     { Write-Host "  $name -> [NOT FOUND]" }
}

Write-Host "`n=== Domain ==="
$cs = Get-WmiObject Win32_ComputerSystem
Write-Host "  Domain: $($cs.Domain), PartOfDomain: $($cs.PartOfDomain)"
