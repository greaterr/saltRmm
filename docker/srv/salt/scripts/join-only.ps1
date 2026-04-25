$Domain    = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$DomainUser = "Administrator"
$DomainPass = "Admin1234!"

# Flush DNS cache first
Write-Host "Flushing DNS cache..."
Clear-DnsClientCache
ipconfig /flushdns | Out-Null

# Force DNS to use our DC
Write-Host "Setting DNS suffix search list..."
Set-DnsClientGlobalSetting -SuffixSearchList @($Domain)

# Verify DNS resolves DC
Write-Host "Verifying DC resolution..."
$dcIP = (Resolve-DnsName "dc1.$Domain" -Server $DC -Type A -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1).IPAddress
Write-Host "dc1.$Domain -> $dcIP"

# Add DC to hosts file so Windows finds it without DNS
Write-Host "Adding DC to hosts file..."
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsEntry = "$DC dc1.$Domain $Domain"
$hostsContent = Get-Content $hostsPath
if (-not ($hostsContent | Select-String -SimpleMatch "dc1.$Domain")) {
    Add-Content -Path $hostsPath -Value $hostsEntry
    Write-Host "[OK] Added: $hostsEntry"
} else {
    Write-Host "[--] Already in hosts file"
}

# Force Kerberos to use TCP instead of UDP (Docker blocks UDP 88)
Write-Host "Forcing Kerberos TCP mode..."
$kerbKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters"
if (-not (Test-Path $kerbKey)) { New-Item -Path $kerbKey -Force | Out-Null }
Set-ItemProperty -Path $kerbKey -Name "MaxPacketSize" -Value 1 -Type DWord
Write-Host "[OK] Kerberos TCP forced (MaxPacketSize=1)"

# Switch network profile from Public to Private (required for domain join)
Write-Host "Checking network profile..."
$profiles = Get-NetConnectionProfile
foreach ($profile in $profiles) {
    Write-Host "    $($profile.Name): $($profile.NetworkCategory)"
    if ($profile.NetworkCategory -eq "Public") {
        Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private
        Write-Host "[OK] Switched '$($profile.Name)' from Public to Private"
    }
}

# Flush again after hosts update
Clear-DnsClientCache
ipconfig /flushdns | Out-Null
Start-Sleep -Seconds 2

# Verify
$check = Resolve-DnsName "dc1.$Domain" -Type A -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1
Write-Host "dc1.$Domain resolves to: $($check.IPAddress)"

# Join domain via WMI directly
Write-Host "Joining $Domain via WMI..."
try {
    $comp = Get-WmiObject -Class Win32_ComputerSystem
    # FJoinOptions: 1=domain, 2=create account, 32=password pass, 64=unsecure join
    # 3 = join domain + create account
    $result = $comp.JoinDomainOrWorkgroup(
        $Domain,
        $DomainPass,
        "$Domain\$DomainUser",
        $null,
        3
    )
    $code = $result.ReturnValue
    Write-Host "[--] WMI return code: $code"
    switch ($code) {
        0  { Write-Host "[OK] Joined $Domain successfully - REBOOT REQUIRED" }
        5  { Write-Host "[FAIL] Access denied" }
        53 { Write-Host "[FAIL] Network path not found - DC unreachable" }
        87 { Write-Host "[FAIL] Invalid parameter" }
        1355 { Write-Host "[FAIL] Domain not found or cannot be contacted" }
        2691 { Write-Host "[FAIL] Already joined to this domain" }
        default { Write-Host "[FAIL] Unknown error: $code" }
    }
} catch {
    Write-Host "[FAIL] WMI exception: $($_.Exception.Message)"
}
