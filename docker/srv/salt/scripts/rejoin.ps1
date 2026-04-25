$Domain    = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$AdminUser = "Administrator"
$AdminPass = "Admin1234!"
$CompPass  = "Comp1234!"

Write-Host "=== Re-joining domain properly ==="

# Ensure Kerberos uses TCP
$kerbKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters"
if (-not (Test-Path $kerbKey)) { New-Item $kerbKey -Force | Out-Null }
Set-ItemProperty $kerbKey -Name "MaxPacketSize" -Value 1 -Type DWord
Write-Host "[OK] Kerberos TCP forced"

# Ensure hosts entry
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$content = Get-Content $hostsPath -Raw
if ($content -notmatch [regex]::Escape("dc1.$Domain")) {
    Add-Content $hostsPath "`n$DC dc1.$Domain $Domain"
    Write-Host "[OK] Hosts updated"
}

# Network profile - Private
Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq "Public" } | ForEach-Object {
    Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
    Write-Host "[OK] Network set to Private"
}

# Flush DNS
Clear-DnsClientCache
ipconfig /flushdns | Out-Null

# Try Add-Computer
Write-Host "`nJoining via Add-Computer..."
$secPass = ConvertTo-SecureString $AdminPass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("$AdminUser@$Domain", $secPass)
try {
    Add-Computer -DomainName $Domain -Credential $cred -Force -ErrorAction Stop
    Write-Host "[OK] Add-Computer succeeded - REBOOT REQUIRED"
    exit 0
} catch {
    Write-Host "[FAIL] Add-Computer: $($_.Exception.Message)"
}

# Fallback: unsecured join with pre-created account
Write-Host "`nFallback: WMI unsecured join..."
$comp = Get-WmiObject Win32_ComputerSystem
$r = $comp.JoinDomainOrWorkgroup($Domain, $CompPass, $null, $null, 96)
Write-Host "WMI result: $($r.ReturnValue)"
if ($r.ReturnValue -eq 0) {
    Write-Host "[OK] WMI joined - REBOOT REQUIRED"
} elseif ($r.ReturnValue -eq 2691) {
    Write-Host "[--] Already joined (2691) - try reboot"
} else {
    Write-Host "[FAIL] Error $($r.ReturnValue)"
    
    # Last resort: fix registry manually
    Write-Host "`nFixing registry domain join manually..."
    $netParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
    Set-ItemProperty $netParams -Name "Domain" -Value $Domain -Type String
    Set-ItemProperty $netParams -Name "NV Domain" -Value $Domain -Type String
    
    $lsaKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    Set-ItemProperty $lsaKey -Name "disabledomaincreds" -Value 0 -Type DWord
    
    Write-Host "[OK] Registry patched - REBOOT and check"
}
