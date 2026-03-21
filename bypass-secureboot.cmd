@echo off
title FlexTPM - Bypass Secure Boot Check
echo.
echo  FlexTPM - Windows 11 Secure Boot Requirement Bypass
echo  ====================================================
echo.
echo  This bypasses the Windows 11 Secure Boot check
echo  for both upgrades and clean installs.
echo  TPM requirement remains enforced.
echo.

:: For in-place upgrades (setup.exe from inside Windows)
reg add "HKLM\SYSTEM\Setup\MoSetup" /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f >nul 2>&1

:: For clean installs (booting from USB)
reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f >nul 2>&1

if %errorlevel%==0 (
    echo  [OK] Secure Boot check bypassed successfully.
    echo.
    echo  You can now run Windows 11 setup.
) else (
    echo  [ERROR] Failed to set registry key. Make sure you're running as admin.
)

echo.
pause
