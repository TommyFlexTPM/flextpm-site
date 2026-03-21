Write-Host "=== Re-enabling services ===" -Fore Cyan
sc.exe config FlexTpmEngine start= auto
sc.exe config FlexTpmLink start= auto  
sc.exe config TBS start= auto
sc.exe start FlexTpmEngine 2>$null
Start-Sleep 3
sc.exe start FlexTpmLink 2>$null
Start-Sleep 2
sc.exe start TBS 2>$null
Start-Sleep 3
Write-Host "`n=== Get-Tpm ===" -Fore Cyan
Get-Tpm | Format-List
