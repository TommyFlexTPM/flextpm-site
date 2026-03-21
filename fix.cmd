@echo off
NET SESSION >/dev/null 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)
echo Downloading test...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest 'https://flextpm.com/tbs_test.ps1' -OutFile 'C:\FlexTPM\tbs_test.ps1'"
echo Running...
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\FlexTPM\tbs_test.ps1"
pause
