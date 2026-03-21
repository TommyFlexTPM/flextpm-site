@echo off
title FlexTPM - Bypass Secure Boot Check
echo.
echo  FlexTPM - Windows 11 Requirement Bypass
echo  =========================================
echo.
echo  Bypasses Windows 11 hardware checks (Secure Boot, TPM, etc.)
echo  for both upgrades and clean installs.
echo  Run as administrator before starting Windows 11 setup.
echo.

:: For in-place upgrades (setup.exe from inside Windows)
reg add "HKLM\SYSTEM\Setup\MoSetup" /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f >nul 2>&1

:: LabConfig keys for setup checks
reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassTPMCheck /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassRAMCheck /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassStorageCheck /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassCPUCheck /t REG_DWORD /d 1 /f >nul 2>&1

if %errorlevel%==0 (
    echo  [OK] All hardware checks bypassed successfully.
    echo.
    echo  You can now run Windows 11 setup.
) else (
    echo  [ERROR] Failed to set registry key. Make sure you're running as admin.
)

echo.
pause
