$Domain = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress

Write-Host "=== Force DC via registry ==="

# Method 1: NetLogon DomainControllerAddresses
$nlKey = "HKLM:\SYSTEM\CurrentControlSet\Services\NetLogon\Parameters"
if (-not (Test-Path $nlKey)) { New-Item $nlKey -Force | Out-Null }
Set-ItemProperty $nlKey -Name "SiteName"       -Value "" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty $nlKey -Name "NegativeCachePeriod" -Value 0 -Type DWord
Write-Host "[OK] NetLogon cache cleared"

# Method 2: DNS Conditional Forwarder via registry
# Tell Windows DNS client to use our server for rmm.lan zone
Write-Host "Adding DNS conditional forwarder for $Domain..."
$dnsKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
if (-not (Test-Path $dnsKey)) { New-Item $dnsKey -Force | Out-Null }
# QueryPolicy per zone
$zoneKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DnsPolicy\$Domain"
if (-not (Test-Path $zoneKey)) { New-Item -Path $zoneKey -Force | Out-Null }
Set-ItemProperty $zoneKey -Name "VersionNumber"  -Value 2 -Type DWord
Set-ItemProperty $zoneKey -Name "GenericDNSServers" -Value $DC -Type String
Set-ItemProperty $zoneKey -Name "IPSECCARestriction" -Value 0 -Type DWord
Write-Host "[OK] DNS policy zone added for $Domain -> $DC"

# Also add for _msdcs subdomain
$msdcsKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DnsPolicy\_msdcs.$Domain"
if (-not (Test-Path $msdcsKey)) { New-Item -Path $msdcsKey -Force | Out-Null }
Set-ItemProperty $msdcsKey -Name "VersionNumber"  -Value 2 -Type DWord
Set-ItemProperty $msdcsKey -Name "GenericDNSServers" -Value $DC -Type String
Set-ItemProperty $msdcsKey -Name "IPSECCARestriction" -Value 0 -Type DWord
Write-Host "[OK] DNS policy zone added for _msdcs.$Domain -> $DC"

# Flush and restart
ipconfig /flushdns | Out-Null
Clear-DnsClientCache
Start-Sleep -Seconds 3

Write-Host "`nVerifying SRV..."
@("_ldap._tcp.dc._msdcs.$Domain","_kerberos._tcp.dc._msdcs.$Domain") | ForEach-Object {
    $q = $_
    try {
        $r = Resolve-DnsName $q -Type SRV -ErrorAction Stop | Select-Object -First 1
        Write-Host "  [OK] $q -> $($r.NameTarget):$($r.Port)"
    } catch {
        Write-Host "  [FAIL] $q"
    }
}

Write-Host "`nnltest..."
$nl = & nltest /dsgetdc:$Domain /force 2>&1
Write-Host ($nl -join "`n")

# Try join if nltest succeeds
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nJoining domain..."
    $securePass = ConvertTo-SecureString "Admin1234!" -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential("Administrator@$Domain", $securePass)
    try {
        Add-Computer -DomainName $Domain -Credential $cred -Force -ErrorAction Stop
        Write-Host "[OK] Joined $Domain - REBOOT REQUIRED"
    } catch {
        Write-Host "[FAIL] $($_.Exception.Message)"
    }
}
