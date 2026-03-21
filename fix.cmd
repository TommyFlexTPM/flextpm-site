@echo off
NET SESSION >/dev/null 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)
echo === FlexTPM Provisioning ===
echo.
echo Downloading repair script...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest 'https://flextpm.com/repair_tpm.ps1' -OutFile 'C:\FlexTPM\repair_tpm.ps1'; Write-Host 'Downloaded'"
echo.
echo Running repair...
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\FlexTPM\repair_tpm.ps1" -InstallDir "C:\FlexTPM" -Force
echo.
echo === Get-Tpm ===
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Tpm | fl TpmPresent, TpmReady"
echo.
echo Done.
pause >/dev/null
