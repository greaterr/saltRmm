# Update DNS server on Windows to current DC IP
$NewDNSServer = "192.168.3.137"

Write-Host "Updating DNS server to $NewDNSServer..."

# Get all network adapters that have DNS configured
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

foreach ($adapter in $adapters) {
    Write-Host "Setting DNS on $($adapter.Name)..."
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $NewDNSServer
}

# Flush DNS cache
Clear-DnsClientCache
ipconfig /flushdns | Out-Null

# Verify
$dns = Get-DnsClientServerAddress | Where-Object { $_.ServerAddresses -ne $null } | Select-Object -First 1
Write-Host "[OK] DNS server set to: $($dns.ServerAddresses)"

Write-Host "Done. Restart salt-minion if needed."
