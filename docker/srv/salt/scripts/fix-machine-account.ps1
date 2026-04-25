$Domain   = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$CompPass = "Comp1234!"

Write-Host "=== Fixing machine account LSA secret ==="

# Check current state
$cs = Get-WmiObject Win32_ComputerSystem
Write-Host "PartOfDomain: $($cs.PartOfDomain), Domain: $($cs.Domain)"

# Set machine password in LSA via ksetup
Write-Host "`n[1] ksetup - configure Kerberos realm..."
$out = & ksetup /setdomain $Domain 2>&1; Write-Host "    $out"
$out = & ksetup /addkdc $Domain $DC 2>&1; Write-Host "    $out"
$out = & ksetup /setcomputerpassword $CompPass 2>&1; Write-Host "    $out"

# Set NetLogon parameters
Write-Host "`n[2] Setting NetLogon parameters..."
$nlKey = "HKLM:\SYSTEM\CurrentControlSet\Services\NetLogon\Parameters"
Set-ItemProperty $nlKey -Name "Domain" -Value $Domain -Type String -ErrorAction SilentlyContinue
Set-ItemProperty $nlKey -Name "DomainName" -Value $Domain -Type String -ErrorAction SilentlyContinue
Set-ItemProperty $nlKey -Name "DatabasePath" -Value "%SystemRoot%\netlogon.chg" -Type String -ErrorAction SilentlyContinue
Write-Host "    [OK]"

# Set Tcpip domain
$tcpKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
Set-ItemProperty $tcpKey -Name "Domain" -Value $Domain
Set-ItemProperty $tcpKey -Name "NV Domain" -Value $Domain
Write-Host "[OK] TCP/IP domain set"

# Update DNS suffix
Set-DnsClientGlobalSetting -SuffixSearchList @($Domain) -ErrorAction SilentlyContinue
Write-Host "[OK] DNS suffix set"

# Verify
Write-Host "`n[3] Verifying registry join state..."
$joinKey = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName"
Write-Host "    ComputerName: $((Get-ItemProperty $joinKey).ComputerName)"

$domainInfo = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction SilentlyContinue
Write-Host "    CachedLogonsCount: $($domainInfo.CachedLogonsCount)"
Write-Host "    DefaultDomainName: $($domainInfo.DefaultDomainName)"

Write-Host "`n=== Rebooting in 5 seconds ==="
Start-Sleep 2
Restart-Computer -Force
