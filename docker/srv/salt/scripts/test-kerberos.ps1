$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress

Write-Host "Testing Kerberos UDP/TCP port 88..."

# TCP 88
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($DC, 88)
    Write-Host "[OK] TCP 88 reachable"
    $tcp.Close()
} catch {
    Write-Host "[FAIL] TCP 88: $($_.Exception.Message)"
}

# UDP 88 - send AS-REQ minimal packet
try {
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.Client.ReceiveTimeout = 3000
    $udp.Connect($DC, 88)
    # Minimal Kerberos AS-REQ
    $bytes = [byte[]](0x6a,0x07,0x30,0x05,0xa1,0x03,0x02,0x01,0x05)
    $udp.Send($bytes, $bytes.Length) | Out-Null
    try {
        $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $resp = $udp.Receive([ref]$ep)
        Write-Host "[OK] UDP 88 got response ($($resp.Length) bytes) from $($ep.Address)"
    } catch {
        Write-Host "[WARN] UDP 88 no response (timeout) - port may be filtered"
    }
    $udp.Close()
} catch {
    Write-Host "[FAIL] UDP 88: $($_.Exception.Message)"
}

# Try kinit equivalent - get TGT
Write-Host "`nTrying to get Kerberos TGT..."
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
try {
    $pc = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
        [System.DirectoryServices.AccountManagement.ContextType]::Domain,
        $DC
    )
    $valid = $pc.ValidateCredentials("Administrator", "Admin1234!")
    Write-Host "[OK] Credentials valid: $valid"
} catch {
    Write-Host "[FAIL] PrincipalContext: $($_.Exception.Message)"
}
