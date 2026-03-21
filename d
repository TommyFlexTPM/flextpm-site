Write-Host "=== FlexTPM Diagnostic ===" -Fore Cyan
Write-Host "`nUMDF Driver:" -Fore Yellow
Get-Process WUDFHost -EA SilentlyContinue | ForEach-Object { $_.Modules } | Where-Object { $_.ModuleName -match 'flextpm' } | ForEach-Object { Write-Host "  YES: $($_.FileName)" -Fore Green }
if (-not (Get-Process WUDFHost -EA SilentlyContinue | ForEach-Object { $_.Modules } | Where-Object { $_.ModuleName -match 'flextpm' })) { Write-Host "  NOT LOADED" -Fore Red }
Write-Host "`nServices:" -Fore Yellow
foreach($s in @('FlexTpmEngine','FlexTpmLink','TBS')){$v=Get-Service $s -EA SilentlyContinue; if($v){Write-Host "  $s : $($v.Status) ($($v.StartType))"}else{Write-Host "  $s : NOT FOUND" -Fore Red}}
Write-Host "`nDevices:" -Fore Yellow
Get-PnpDevice -Class SecurityDevices -EA SilentlyContinue | ForEach-Object { Write-Host "  $($_.InstanceId): $($_.Status)" }
Write-Host "`nGet-Tpm:" -Fore Yellow
try{Get-Tpm|fl}catch{Write-Host "  $($_.Exception.Message)" -Fore Red}
