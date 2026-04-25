$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$lines = Get-Content $hostsPath
$cleaned = $lines | Where-Object { $_ -notmatch "rmm\.lan" }
Set-Content $hostsPath $cleaned
Write-Host "Done. Remaining entries:"
Get-Content $hostsPath | Where-Object { $_ -notmatch "^#" -and $_.Trim() -ne "" }
