$Domain     = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$CompPass   = "Comp1234!"
$AdminUser  = "Administrator"
$AdminPass  = "Admin1234!"

Write-Host "=== Manual Domain Join via Registry ==="

# Method: Set domain join info directly in registry
# This is what djoin /requestodj does internally

$lsaKey  = "HKLM:\SECURITY\Policy\Secrets"
$lmKey   = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$netKey  = "HKLM:\SYSTEM\CurrentControlSet\Services\NetLogon\Parameters"

# Try Add-Computer with pre-created account (no need for PDC)
Write-Host "`nAttempting join with pre-created account..."
$secPass = ConvertTo-SecureString $AdminPass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("$AdminUser@$Domain", $secPass)

try {
    # /OPTIONS:35 = join + no account creation needed (account exists)
    $comp = Get-WmiObject Win32_ComputerSystem
    # FJoinOptions: 1=join domain, 2=create account, 32=Win9xUpgrade, 64=UnsecuredJoin
    # Without 2 = use existing account
    $r = $comp.JoinDomainOrWorkgroup($Domain, $AdminPass, "$AdminUser@$Domain", $null, 1)
    Write-Host "WMI (no create): $($r.ReturnValue)"
    if ($r.ReturnValue -eq 0) {
        Write-Host "[OK] Joined! Reboot required."
        exit 0
    }
} catch {
    Write-Host "[--] $($_.Exception.Message)"
}

# Method 2: UnsecuredJoin (64) - doesn't use Kerberos
Write-Host "`nTrying unsecured join (no Kerberos)..."
try {
    $comp = Get-WmiObject Win32_ComputerSystem
    # 64 = UnsecuredJoin (uses machine password directly, no Kerberos needed)
    # 32+64 = PasswordPass + UnsecuredJoin
    $r = $comp.JoinDomainOrWorkgroup($Domain, $CompPass, $null, $null, 96)
    Write-Host "WMI unsecured result: $($r.ReturnValue)"
    if ($r.ReturnValue -eq 0) {
        Write-Host "[OK] Unsecured join successful! Reboot required."
        exit 0
    } else {
        switch ($r.ReturnValue) {
            5    { Write-Host "[FAIL] Access denied" }
            53   { Write-Host "[FAIL] Network path not found" }
            87   { Write-Host "[FAIL] Invalid parameter" }
            1326 { Write-Host "[FAIL] Logon failure (wrong password)" }
            1355 { Write-Host "[FAIL] Domain not found" }
            2691 { Write-Host "[FAIL] Already joined" }
            default { Write-Host "[FAIL] Error: $($r.ReturnValue)" }
        }
    }
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)"
}
