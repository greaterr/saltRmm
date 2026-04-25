Write-Host "=== Security Policy & Network Check ==="

# LAN Manager auth level
Write-Host "`n[1] LM Authentication Level..."
$lm = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -ErrorAction SilentlyContinue).LmCompatibilityLevel
Write-Host "    LmCompatibilityLevel: $lm (5=NTLMv2 only, 3=default)"

# Require signing
Write-Host "`n[2] SMB/LDAP signing..."
$signing = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "RequireSecuritySignature" -ErrorAction SilentlyContinue).RequireSecuritySignature
Write-Host "    RequireSecuritySignature: $signing"

# Kerberos settings
Write-Host "`n[3] Kerberos registry settings..."
$kerbPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters"
if (Test-Path $kerbPath) {
    Get-ItemProperty $kerbPath | Format-List
} else {
    Write-Host "    (no Kerberos Parameters key)"
}

# Check if domain join is restricted by policy
Write-Host "`n[4] Domain join policy..."
$djPolicy = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -ErrorAction SilentlyContinue)
Write-Host "    $djPolicy"

# Network profile
Write-Host "`n[5] Network connection profile..."
Get-NetConnectionProfile | Format-Table Name, NetworkCategory, IPv4Connectivity -AutoSize

# Check DNS client settings
Write-Host "`n[6] DNS Client settings..."
Get-DnsClientGlobalSetting | Format-List

# Windows version
Write-Host "`n[7] Windows version..."
[System.Environment]::OSVersion.Version
(Get-WmiObject Win32_OperatingSystem).Caption

# Check if machine has corporate proxy or GPO blocking
Write-Host "`n[8] Proxy settings..."
(Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue) | Select-Object ProxyEnable, ProxyServer | Format-List

# netlogon service status
Write-Host "`n[9] Netlogon service..."
Get-Service -Name Netlogon -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType | Format-Table
