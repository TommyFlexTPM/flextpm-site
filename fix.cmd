@echo off
NET SESSION >/dev/null 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)
echo === FlexTPM Carbon Copy Fix ===
echo.
echo Downloading working config from main machine...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://flextpm.com/'; Invoke-WebRequest ($u+'export_wmi.reg') -OutFile C:\FlexTPM\wmi.reg; Invoke-WebRequest ($u+'export_tbs.reg') -OutFile C:\FlexTPM\tbs.reg; Invoke-WebRequest ($u+'export_engine.reg') -OutFile C:\FlexTPM\engine.reg; Invoke-WebRequest ($u+'export_link.reg') -OutFile C:\FlexTPM\link.reg; Invoke-WebRequest ($u+'repair_tpm.ps1') -OutFile C:\FlexTPM\repair_tpm.ps1; Write-Host 'Downloaded'"
echo.
echo Stopping services...
sc stop TBS >/dev/null 2>&1
sc stop FlexTpmLink >/dev/null 2>&1
sc stop FlexTpmEngine >/dev/null 2>&1
timeout /t 2 /nobreak >/dev/null
echo.
echo Importing exact registry from working machine...
reg import C:\FlexTPM\wmi.reg
reg import C:\FlexTPM\tbs.reg
reg import C:\FlexTPM\engine.reg
reg import C:\FlexTPM\link.reg
echo.
echo Starting services...
sc start FlexTpmEngine
timeout /t 3 /nobreak >/dev/null
sc start FlexTpmLink
timeout /t 2 /nobreak >/dev/null
sc start TBS
timeout /t 3 /nobreak >/dev/null
echo.
echo === Get-Tpm ===
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Tpm | fl"
pause
