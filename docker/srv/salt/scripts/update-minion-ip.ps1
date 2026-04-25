$MasterFQDN = "macbook-pro-timur.rmm.lan"
$MinionConf  = "C:\ProgramData\Salt Project\Salt\conf\minion"

Write-Host "Updating salt-minion master to $MasterFQDN..."

$content = Get-Content $MinionConf -Raw

# Replace any existing master: line (IP or hostname)
$content = $content -replace '(?m)^master:.*$', "master: $MasterFQDN"

# If no master line found - append it
if ($content -notmatch "master: $([regex]::Escape($MasterFQDN))") {
    $content += "`nmaster: $MasterFQDN"
}

Set-Content $MinionConf $content

# Verify
$check = (Get-Content $MinionConf | Select-String "^master:").Line
Write-Host "[OK] Config: $check"

Write-Host "Restarting salt-minion..."
Stop-Service salt-minion -ErrorAction SilentlyContinue
Start-Sleep 2
Start-Service salt-minion
Write-Host "[OK] Done"
