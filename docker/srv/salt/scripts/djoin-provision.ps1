$Domain    = "rmm.lan"
$DC = (Resolve-DnsName "dc1.rmm.lan" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
$Computer  = $env:COMPUTERNAME
$BlobFile  = "C:\Windows\Temp\djoin-blob.txt"
$DomainUser = "Administrator"
$DomainPass = "Admin1234!"

Write-Host "=== Offline Domain Join via djoin ==="
Write-Host "Computer: $Computer"
Write-Host "Domain:   $Domain"
Write-Host "DC:       $DC"

# Step 1: Create computer account on DC via djoin /provision
# We run this locally pointing at DC directly
Write-Host "`nProvisioning computer account on DC..."
$result = & djoin.exe /provision /domain $Domain /machine $Computer /dcname $DC /savefile $BlobFile /reuse 2>&1
Write-Host $result

if (Test-Path $BlobFile) {
    Write-Host "[OK] Blob file created: $BlobFile"

    # Step 2: Apply blob to join domain (offline)
    Write-Host "`nApplying domain join blob..."
    $result2 = & djoin.exe /requestodj /loadfile $BlobFile /windowspath $env:SystemRoot /localos 2>&1
    Write-Host $result2

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Domain join applied - REBOOT REQUIRED"
    } else {
        Write-Host "[FAIL] djoin /requestodj failed"
    }
} else {
    Write-Host "[FAIL] Blob file not created - djoin /provision failed"
    Write-Host "Trying alternative: direct WMI with UPN..."

    # Last resort: try with explicit DC in domain string
    $comp = Get-WmiObject Win32_ComputerSystem
    $r = $comp.JoinDomainOrWorkgroup($Domain, $DomainPass, "$DomainUser@$Domain", $null, 3)
    Write-Host "WMI result: $($r.ReturnValue)"
}
