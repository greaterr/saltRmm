$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$Domain = "rmm.lan"

Write-Host "=== Deep DC connectivity test ==="

# RPC endpoint mapper port 135
Write-Host "`n[1] RPC Endpoint Mapper (135)..."
try {
    $t = New-Object System.Net.Sockets.TcpClient($DC, 135)
    Write-Host "[OK] Port 135 open"
    $t.Close()
} catch { Write-Host "[FAIL] $($_.Exception.Message)" }

# SMB port 445
Write-Host "[2] SMB (445)..."
try {
    $t = New-Object System.Net.Sockets.TcpClient($DC, 445)
    Write-Host "[OK] Port 445 open"
    $t.Close()
} catch { Write-Host "[FAIL] $($_.Exception.Message)" }

# NetLogon via UNC
Write-Host "`n[3] SYSVOL access via UNC..."
try {
    $path = "\\$DC\SYSVOL"
    $exists = Test-Path $path -ErrorAction Stop
    Write-Host "[OK] $path accessible: $exists"
} catch { Write-Host "[FAIL] $($_.Exception.Message)" }

# NETLOGON share
Write-Host "[4] NETLOGON share..."
try {
    $path = "\\$DC\NETLOGON"
    $exists = Test-Path $path -ErrorAction Stop
    Write-Host "[OK] $path accessible: $exists"
} catch { Write-Host "[FAIL] $($_.Exception.Message)" }

# net view
Write-Host "`n[5] net view..."
$out = & net view \\$DC 2>&1
Write-Host $out

# Check Windows event log for Netlogon errors
Write-Host "`n[6] Recent Netlogon events..."
Get-EventLog -LogName System -Source "NETLOGON" -Newest 5 -ErrorAction SilentlyContinue |
    Select-Object TimeGenerated, EntryType, Message |
    Format-List

# Check if firewall blocks outbound
Write-Host "[7] Firewall outbound rules for domain join ports..."
Get-NetFirewallRule -Direction Outbound -Enabled True -Action Block -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "kerberos|ldap|netlogon|445|88|389" } |
    Select-Object DisplayName, Action | Format-Table
