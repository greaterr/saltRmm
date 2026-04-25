$Domain = "rmm.lan"

Restart-Service Dnscache -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Clear-DnsClientCache

Write-Host "SRV records via system DNS:"
@(
    "_ldap._tcp.dc._msdcs.$Domain",
    "_kerberos._tcp.dc._msdcs.$Domain",
    "_ldap._tcp.$Domain",
    "_kerberos._tcp.$Domain"
) | ForEach-Object {
    $q = $_
    try {
        $r = Resolve-DnsName $q -Type SRV -ErrorAction Stop | Select-Object -First 1
        Write-Host "  [OK] $q -> $($r.NameTarget):$($r.Port)"
    } catch {
        Write-Host "  [FAIL] $q"
    }
}

Write-Host "`nnltest:"
$nl = & nltest /dsgetdc:$Domain /force 2>&1
Write-Host ($nl -join "`n")
