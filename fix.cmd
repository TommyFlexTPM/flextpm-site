@echo off
NET SESSION >/dev/null 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)
echo === FlexTPM Fix ===
echo Downloading latest repair script...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://flextpm.com/repair_tpm.ps1' -OutFile 'C:\FlexTPM\repair_tpm.ps1'"
echo Starting services...
sc config FlexTpmEngine start= auto >/dev/null 2>&1
sc config FlexTpmLink start= auto >/dev/null 2>&1
sc config TBS start= auto >/dev/null 2>&1
sc start FlexTpmEngine >/dev/null 2>&1
timeout /t 3 /nobreak >/dev/null
sc start FlexTpmLink >/dev/null 2>&1
timeout /t 2 /nobreak >/dev/null
sc start TBS >/dev/null 2>&1
timeout /t 3 /nobreak >/dev/null
echo Running repair...
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\FlexTPM\repair_tpm.ps1" -InstallDir "C:\FlexTPM" -Force
timeout /t 3 /nobreak >/dev/null
echo.
echo === Get-Tpm ===
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Tpm | fl"
pause
