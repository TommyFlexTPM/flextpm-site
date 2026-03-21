Write-Host "=== FlexTPM Repair ===" -Fore Cyan
& "C:\FlexTPM\repair_tpm.ps1" -InstallDir "C:\FlexTPM" -Force 2>&1
Write-Host "`n=== Get-Tpm ===" -Fore Cyan
Get-Tpm | Format-List
