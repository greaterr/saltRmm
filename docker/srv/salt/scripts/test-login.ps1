$Domain = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$User   = "aduser"
$Pass   = "User1234!"

Write-Host "=== Testing domain user login ==="

# Check Kerberos TCP setting
$kerbKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters"
$maxPkt = (Get-ItemProperty $kerbKey -ErrorAction SilentlyContinue).MaxPacketSize
Write-Host "[1] MaxPacketSize (Kerberos TCP): $maxPkt (must be 1)"

# Check DC reachable
Write-Host "`n[2] DC ports..."
foreach ($port in @(88, 389, 445)) {
    try {
        $t = New-Object System.Net.Sockets.TcpClient($DC, $port)
        Write-Host "    [OK] TCP $port"
        $t.Close()
    } catch { Write-Host "    [FAIL] TCP $port" }
}

# Try Kerberos TGT via .NET
Write-Host "`n[3] PrincipalContext login test..."
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
try {
    $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
        [System.DirectoryServices.AccountManagement.ContextType]::Domain, $DC
    )
    $ok = $ctx.ValidateCredentials($User, $Pass)
    Write-Host "    [$(if($ok){'OK'}else{'FAIL'})] Credentials valid: $ok"
} catch {
    Write-Host "    [FAIL] $($_.Exception.Message)"
}

# Check if machine is actually domain joined
Write-Host "`n[4] Domain membership..."
$cs = Get-WmiObject Win32_ComputerSystem
Write-Host "    Domain: $($cs.Domain)"
Write-Host "    PartOfDomain: $($cs.PartOfDomain)"

# Check netlogon secure channel
Write-Host "`n[5] Secure channel test..."
$sc = & nltest /sc_query:$Domain 2>&1
Write-Host "    $($sc -join ' | ')"

# Event log - last auth failures
Write-Host "`n[6] Recent auth failures (Event 4625)..."
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625} -MaxEvents 3 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Message | ForEach-Object {
        Write-Host "    $($_.TimeCreated): $(($_.Message -split '\n')[0])"
    }
