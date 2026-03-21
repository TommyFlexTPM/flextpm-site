@echo off
NET SESSION >/dev/null 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
echo === FlexTPM Provisioning ===
echo.
echo Downloading...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest 'https://flextpm.com/provision.ps1' -OutFile 'C:\FlexTPM\provision.ps1'; Write-Host 'OK'"
echo.
echo Running...
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\FlexTPM\provision.ps1"
echo.
echo Press any key...
pause >/dev/null
