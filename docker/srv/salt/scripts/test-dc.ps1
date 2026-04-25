$Domain = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$User   = "Administrator@rmm.lan"
$Pass   = "Admin1234!"

Write-Host "=== Testing DC contact ==="

# Test 1: DirectoryContext
Write-Host "`n[1] DirectoryContext test..."
try {
    $ctx = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext(
        [System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain,
        $Domain, $User, $Pass
    )
    $dom = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($ctx)
    Write-Host "[OK] Domain found: $($dom.Name), PDC: $($dom.PdcRoleOwner)"
} catch {
    Write-Host "[FAIL] DirectoryContext: $($_.Exception.Message)"
}

# Test 2: LDAP bind
Write-Host "`n[2] LDAP bind test..."
try {
    Add-Type -AssemblyName System.DirectoryServices
    $de = New-Object System.DirectoryServices.DirectoryEntry(
        "LDAP://$DC/DC=rmm,DC=lan", $User, $Pass,
        [System.DirectoryServices.AuthenticationTypes]::SecureSocketsLayer -bor
        [System.DirectoryServices.AuthenticationTypes]::ServerBind
    )
    $name = $de.Name
    Write-Host "[OK] LDAP bind: $name"
} catch {
    Write-Host "[FAIL] LDAP: $($_.Exception.Message)"
}

# Test 3: Kerberos ticket
Write-Host "`n[3] Kerberos test (klist)..."
$klist = & klist 2>&1
Write-Host $klist

# Test 4: WMI join simulation
Write-Host "`n[4] WMI JoinDomainOrWorkgroup test..."
try {
    $comp = Get-WmiObject Win32_ComputerSystem
    Write-Host "[--] Current: Domain=$($comp.Domain), PartOfDomain=$($comp.PartOfDomain)"
    $result = $comp.JoinDomainOrWorkgroup($Domain, $Pass, $User, $null, 3)
    Write-Host "[--] WMI result code: $($result.ReturnValue)"
    if ($result.ReturnValue -eq 0) {
        Write-Host "[OK] WMI join successful - reboot required"
    } else {
        Write-Host "[FAIL] WMI error code: $($result.ReturnValue)"
        # https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/joindomainorworkgroup-method-in-class-win32-computersystem
    }
} catch {
    Write-Host "[FAIL] WMI: $($_.Exception.Message)"
}
