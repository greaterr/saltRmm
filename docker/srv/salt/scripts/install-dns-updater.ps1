$Domain   = "rmm.lan"
$TaskName = "SaltRmm-UpdateDNS"
$ScriptPath = "C:\ProgramData\Salt Project\Salt\dns-updater.ps1"

# Script that runs on network change
$ScriptContent = @'
$Domain = "rmm.lan"
$LogFile = "C:\ProgramData\Salt Project\Salt\dns-updater.log"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts $msg" | Add-Content $LogFile
}

# Find DC by trying known gateway + scanning common IPs
# Strategy: probe port 389 (LDAP) on all hosts in current subnet
$adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -and $_.DefaultIPGateway }
foreach ($a in $adapters) {
    $currentDNS = $a.DNSServerSearchOrder
    $ip = $a.IPAddress[0]
    $subnet = ($ip -split '\.')[0..2] -join '.'

    Write-Log "Network: $ip, subnet: $subnet.0/24, current DNS: $($currentDNS -join ', ')"

    # First try: resolve dc1.rmm.lan via current DNS (may still work)
    $resolved = Resolve-DnsName "dc1.$Domain" -Type A -ErrorAction SilentlyContinue |
        Where-Object { $_.Type -eq "A" } | Select-Object -First 1
    if ($resolved) {
        $dcIP = $resolved.IPAddress
        Write-Log "dc1.$Domain resolved to $dcIP via current DNS"
        if ($currentDNS[0] -ne $dcIP) {
            $a.SetDNSServerSearchOrder(@($dcIP, "8.8.8.8")) | Out-Null
            Write-Log "DNS updated to $dcIP"
        }
        exit 0
    }

    # Second try: scan subnet for LDAP port 389
    Write-Log "DNS failed, scanning $subnet.0/24 for LDAP..."
    $found = $null
    1..254 | ForEach-Object {
        if ($found) { return }
        $testIP = "$subnet.$_"
        $t = New-Object System.Net.Sockets.TcpClient
        $r = $t.BeginConnect($testIP, 389, $null, $null)
        if ($r.AsyncWaitHandle.WaitOne(100, $false)) {
            try { $t.EndConnect($r); $found = $testIP } catch {}
        }
        $t.Close()
    }

    if ($found) {
        Write-Log "Found DC at $found, updating DNS..."
        $a.SetDNSServerSearchOrder(@($found, "8.8.8.8")) | Out-Null
        Write-Log "DNS updated to $found"
    } else {
        Write-Log "DC not found in subnet $subnet.0/24"
    }
}
'@

# Write updater script
$ScriptContent | Set-Content $ScriptPath -Encoding UTF8
Write-Host "[OK] Updater script written to $ScriptPath"

# Register scheduled task triggered on network event
$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -WindowStyle Hidden -File `"$ScriptPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn

# Also trigger on network profile change event
$eventTrigger = New-ScheduledTaskTrigger -AtStartup

$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 3) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

# Network change trigger via CIM event subscription
$cimTrigger = @"
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational">
    <Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[EventID=10000 or EventID=10001]]</Select>
  </Query>
</QueryList>
"@
$eventTrigg = New-ScheduledTaskTrigger -AtStartup

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Updates DNS server to current DC IP on network change" | Out-Null

# Add event-based trigger via XML
$task = Get-ScheduledTask -TaskName $TaskName
$xml = [xml]($task | Export-ScheduledTask)

$ns = "http://schemas.microsoft.com/windows/2004/02/mit/task"
$triggersNode = $xml.Task.Triggers

$eventTrigNode = $xml.CreateElement("EventTrigger", $ns)
$subNode = $xml.CreateElement("Subscription", $ns)
$subNode.InnerText = $cimTrigger
$enabledNode = $xml.CreateElement("Enabled", $ns)
$enabledNode.InnerText = "true"
$eventTrigNode.AppendChild($enabledNode) | Out-Null
$eventTrigNode.AppendChild($subNode) | Out-Null
$triggersNode.AppendChild($eventTrigNode) | Out-Null

$tempXml = "$env:TEMP\saltrmm-task.xml"
$xml.Save($tempXml)
schtasks /Create /TN $TaskName /XML $tempXml /F | Out-Null
Remove-Item $tempXml

Write-Host "[OK] Scheduled task '$TaskName' registered (triggers: logon + network change)"

# Run immediately
Write-Host "Running now..."
Start-ScheduledTask -TaskName $TaskName
Start-Sleep 5
Write-Host "[OK] Done"
