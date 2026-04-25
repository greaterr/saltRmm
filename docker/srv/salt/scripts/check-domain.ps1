# Check domain join status
Write-Host "=== Domain Membership Status ==="
$cs = Get-WmiObject -Class Win32_ComputerSystem
Write-Host "Domain: $($cs.Domain)"
Write-Host "Workgroup: $($cs.Workgroup)"
Write-Host "Part of domain: $($cs.PartOfDomain)"

if ($cs.PartOfDomain) {
    Write-Host "`n=== Domain Controller Info ==="
    $dc = Get-WmiObject -Class Win32_NTDomain
    Write-Host "DC Name: $($dc.DomainName)"
    Write-Host "DC Status: $($dc.Status)"
    
    Write-Host "`n=== Secure Channel Test ==="
    Test-ComputerSecureChannel -Verbose
} else {
    Write-Host "`n[INFO] Not joined to domain"
}
