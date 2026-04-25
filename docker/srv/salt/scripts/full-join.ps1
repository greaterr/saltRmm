$Domain    = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$AdminUser = "Administrator"
$AdminPass = "Admin1234!"

Write-Host "=== Full Domain Join ==="

# 1. Kerberos TCP
$kerbKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters"
if (-not (Test-Path $kerbKey)) { New-Item $kerbKey -Force | Out-Null }
Set-ItemProperty $kerbKey -Name "MaxPacketSize" -Value 1 -Type DWord
Write-Host "[OK] Kerberos TCP"

# 2. Network Private
Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq "Public" } | ForEach-Object {
    Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
    Write-Host "[OK] Network -> Private"
}

# 3. DNS - set DC as primary on all adapters
$adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
foreach ($a in $adapters) {
    $a.SetDNSServerSearchOrder(@($DC, "8.8.8.8")) | Out-Null
    $a.SetDNSDomain($Domain) | Out-Null
}
Set-DnsClientGlobalSetting -SuffixSearchList @($Domain)
Write-Host "[OK] DNS set to $DC"

# 4. Hosts file - clean and update
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hosts = (Get-Content $hostsPath) | Where-Object { $_ -notmatch "rmm\.lan" }
$hosts += "$DC dc1.$Domain"
$hosts += "$DC $Domain"
Set-Content $hostsPath $hosts
Write-Host "[OK] Hosts updated"

# 5. Flush DNS
ipconfig /flushdns | Out-Null
Clear-DnsClientCache
Start-Sleep -Seconds 3

# 6. Verify SRV via explicit DNS server
Write-Host "`n[*] SRV check (explicit DNS)..."
$srv = Resolve-DnsName "_ldap._tcp.dc._msdcs.$Domain" -Type SRV -Server $DC -ErrorAction SilentlyContinue | Select-Object -First 1
if ($srv) { Write-Host "    [OK] SRV: $($srv.NameTarget):$($srv.Port)" }
else { Write-Host "    [--] SRV not found via explicit, continuing anyway..." }

# 7. Verify DC reachable
Write-Host "[*] DC connectivity..."
foreach ($port in @(88, 389, 445)) {
    $t = New-Object System.Net.Sockets.TcpClient; $t.ReceiveTimeout = 2000
    try { $t.Connect($DC, $port); Write-Host "    [OK] TCP $port"; $t.Close() }
    catch { Write-Host "    [FAIL] TCP $port" }
}

# 8. Try Add-Computer with explicit server
Write-Host "`n[*] Add-Computer..."
$secPass = ConvertTo-SecureString $AdminPass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("$AdminUser@$Domain", $secPass)
try {
    Add-Computer -DomainName $Domain -Credential $cred -Force -ErrorAction Stop
    Write-Host "[OK] JOINED! Rebooting..."
    Start-Sleep 2
    Restart-Computer -Force
    exit 0
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)"
}

# 9. Try nltest
Write-Host "`n[*] nltest..."
$nl = & nltest /dsgetdc:$Domain /force /kdc 2>&1
Write-Host ($nl -join "`n")

# 10. Try with NETBIOS name
Write-Host "`n[*] Add-Computer with NETBIOS..."
try {
    Add-Computer -DomainName "RMM" -Credential $cred -Force -ErrorAction Stop
    Write-Host "[OK] JOINED via NETBIOS!"
    Restart-Computer -Force
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)"
}
