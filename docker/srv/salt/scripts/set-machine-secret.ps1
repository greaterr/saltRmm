$Domain    = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$MachPass  = "MachPass1!"
$Computer  = $env:COMPUTERNAME

Write-Host "=== Setting machine account secret ==="

# Step 1: Leave workgroup first (clean state)
$cs = Get-WmiObject Win32_ComputerSystem
Write-Host "Current: Domain=$($cs.Domain), PartOfDomain=$($cs.PartOfDomain)"

# Step 2: Use ksetup to set machine password
Write-Host "`n[1] ksetup setup..."
& ksetup /setdomain $Domain 2>&1 | Out-Null
& ksetup /addkdc $Domain $DC 2>&1 | Out-Null
& ksetup /setmachpassword $MachPass 2>&1 | Write-Host
& ksetup /setcomputerpassword $MachPass 2>&1 | Write-Host

# Step 3: Set via WMI join with exact machine password  
Write-Host "`n[2] WMI join with machine password..."
$r = $cs.JoinDomainOrWorkgroup($Domain, $MachPass, $null, $null, 96)
Write-Host "WMI result: $($r.ReturnValue)"

# Step 4: Write LSA secret via registry workaround
# Set the domain info in Winlogon
Write-Host "`n[3] Setting Winlogon domain..."
$wlKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty $wlKey -Name "DefaultDomainName" -Value "RMM" -Type String
Set-ItemProperty $wlKey -Name "CachedLogonsCount" -Value "10" -Type String

# Set ComputerNamePhysicalDnsDomain  
$cnKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
Set-ItemProperty $cnKey -Name "Domain" -Value $Domain
Set-ItemProperty $cnKey -Name "NV Domain" -Value $Domain
Set-ItemProperty $cnKey -Name "SearchList" -Value $Domain

# NetLogon params
$nlKey = "HKLM:\SYSTEM\CurrentControlSet\Services\NetLogon\Parameters"
Set-ItemProperty $nlKey -Name "DisablePasswordChange" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Step 5: Use nltest to set machine password
Write-Host "`n[4] nltest machine password change..."
$nl = & nltest /sc_change_pwd:$Domain 2>&1
Write-Host "    $nl"

Write-Host "`n=== Done - rebooting ==="
Start-Sleep 2
Restart-Computer -Force
