@echo off
title FlexTPM - Bypass Secure Boot Check
echo.
echo  FlexTPM - Windows 11 Secure Boot Requirement Bypass
echo  ====================================================
echo.
echo  This bypasses the Windows 11 Secure Boot installation
echo  check only. TPM requirement remains enforced.
echo.
echo  Run this during Windows 11 setup (Shift+F10 to open CMD).
echo.

reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f >nul 2>&1

if %errorlevel%==0 (
    echo  [OK] Secure Boot check bypassed successfully.
    echo.
    echo  Close this window and continue the Windows 11 installation.
) else (
    echo  [ERROR] Failed to set registry key. Make sure you're running as admin.
)

echo.
pause
