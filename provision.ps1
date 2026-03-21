Write-Host "=== Fix Win32_Tpm for this Windows build ===" -Fore Cyan

# Find the NATIVE Win32_Tpm.dll from this machine's WinSxS
$native = Get-ChildItem "$env:SystemRoot\WinSxS" -Filter "Win32_Tpm.dll" -Recurse -EA SilentlyContinue | Select-Object -First 1
$nativeMof = Get-ChildItem "$env:SystemRoot\WinSxS" -Filter "Win32_Tpm.mof" -Recurse -EA SilentlyContinue | Select-Object -First 1

if ($native) {
    Write-Host "Found native Win32_Tpm.dll: $($native.FullName)" -Fore Green
    Copy-Item $native.FullName "$env:SystemRoot\System32\wbem\Win32_Tpm.dll" -Force
    Write-Host "Replaced with native version" -Fore Green
} else {
    Write-Host "No native Win32_Tpm.dll in WinSxS" -Fore Yellow
}

if ($nativeMof) {
    Write-Host "Found native Win32_Tpm.mof: $($nativeMof.FullName)" -Fore Green
    Copy-Item $nativeMof.FullName "$env:SystemRoot\System32\wbem\Win32_Tpm.mof" -Force
    mofcomp "$env:SystemRoot\System32\wbem\Win32_Tpm.mof" 2>&1 | Out-Null
    Write-Host "Re-registered native MOF" -Fore Green
} else {
    Write-Host "No native Win32_Tpm.mof in WinSxS" -Fore Yellow
}

# Restart TBS and WMI
Write-Host "`nRestarting services..." -Fore Yellow
Restart-Service TBS -Force -EA SilentlyContinue
Restart-Service Winmgmt -Force -EA SilentlyContinue
Start-Sleep 5

Write-Host "`n=== Get-Tpm ===" -Fore Cyan
try { Get-Tpm | Format-List TpmPresent, TpmReady, ManufacturerIdTxt } catch { Write-Host $_.Exception.Message -Fore Red }
