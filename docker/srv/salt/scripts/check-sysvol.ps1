$DC     = "dc1.rmm.lan"
$User   = "RMM\Administrator"
$Pass   = "Admin1234!"

Write-Host "=== SYSVOL Check ==="
Write-Host "DC: $DC"

# Test SMB port
$t = New-Object System.Net.Sockets.TcpClient
try {
    $t.Connect($DC, 445)
    Write-Host "[OK] SMB port 445 open"
} catch {
    Write-Host "[FAIL] SMB port 445: $($_.Exception.Message)"
}
$t.Close()

# Test net use
Write-Host "`nMounting SYSVOL..."
$cred = New-Object System.Management.Automation.PSCredential($User, (ConvertTo-SecureString $Pass -AsPlainText -Force))

try {
    if (Test-Path Z:) { Remove-PSDrive Z -Force -ErrorAction SilentlyContinue }
    New-PSDrive -Name Z -PSProvider FileSystem -Root "\\$DC\sysvol" -Credential $cred -ErrorAction Stop | Out-Null
    Write-Host "[OK] Mounted \\$DC\sysvol"

    $policies = Get-ChildItem "Z:\rmm.lan\Policies" -ErrorAction Stop
    Write-Host "Policies:"
    $policies | ForEach-Object { Write-Host "  $($_.Name)" }

    $pd = "Z:\rmm.lan\Policies\PolicyDefinitions"
    if (Test-Path $pd) {
        $count = (Get-ChildItem $pd -Recurse -File).Count
        Write-Host "[OK] PolicyDefinitions exists: $count files"
    } else {
        Write-Host "[FAIL] PolicyDefinitions NOT FOUND"
    }

    Remove-PSDrive Z -Force
} catch {
    Write-Host "[FAIL] Mount error: $($_.Exception.Message)"
}
