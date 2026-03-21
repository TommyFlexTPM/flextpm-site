@echo off
NET SESSION >/dev/null 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)
echo === FlexTPM Fix ===
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
powershell -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\FlexTPM\repair_tpm.ps1' -InstallDir 'C:\FlexTPM' -Force 2>&1; Write-Host ''; Write-Host '=== Get-Tpm ===' -Fore Cyan; Get-Tpm | fl"
pause
