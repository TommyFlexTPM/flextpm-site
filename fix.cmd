@echo off
NET SESSION >/dev/null 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)
echo === FlexTPM Provisioning ===
echo.
echo Downloading provisioning script...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest 'https://flextpm.com/provision.ps1' -OutFile 'C:\FlexTPM\provision.ps1'; Write-Host 'Done'"
echo.
echo Running...
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\FlexTPM\provision.ps1"
echo.
pause
