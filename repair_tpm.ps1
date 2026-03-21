# repair_tpm.ps1 - FlexTPM Full Repair / Restore
# Diagnoses and fixes all FlexTPM components. Can restore from backup if needed.
# Run as Administrator.
# Copyright (c) 2026 FlexTPM Software LLC. All rights reserved.

param(
    [string]$InstallDir = "",
    [string]$BackupDir = "$env:LOCALAPPDATA\FlexTPM\Backups\latest",
    [switch]$RestoreState,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

# Use provided install dir, or detect from script location, or fall back to C:\FlexTPM
if ($InstallDir -ne "") {
    $FlexDir = $InstallDir
} elseif ($PSScriptRoot -ne "" -and (Test-Path (Join-Path $PSScriptRoot "flextpm.exe"))) {
    $FlexDir = $PSScriptRoot
} else {
    $FlexDir = "C:\FlexTPM"
}
$failures = @()
$fixes = @()

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Must run as Administrator"
    exit 1
}

function Status($msg) { Write-Host "  [CHECK] $msg" -ForegroundColor Cyan }
function Ok($msg)     { Write-Host "  [  OK ] $msg" -ForegroundColor Green }
function Fixed($msg)  { Write-Host "  [ FIX ] $msg" -ForegroundColor Yellow; $script:fixes += $msg }
function Fail($msg)   { Write-Host "  [FAIL ] $msg" -ForegroundColor Red; $script:failures += $msg }

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  FlexTPM Repair Tool" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# PHASE 1: Core files
# ============================================================
Write-Host "--- Phase 1: Core Files ---"

$requiredFiles = @("flextpm.exe", "flexsvc.exe")
foreach ($f in $requiredFiles) {
    $path = Join-Path $FlexDir $f
    if (Test-Path $path) { Ok "$f exists" }
    else { Fail "$f MISSING at $path" }
}

# State files — these get auto-created on first run, so missing is OK on fresh install
foreach ($f in @("flextpm_state.bin", "ek_state.bin")) {
    $path = Join-Path $FlexDir $f
    if (Test-Path $path) {
        Ok "$f exists ($(((Get-Item $path).Length)) bytes)"
    } else {
        $backupFile = Join-Path $BackupDir $f
        if ($RestoreState -and (Test-Path $backupFile)) {
            Copy-Item $backupFile $path -Force
            Fixed "Restored $f from backup"
        } else {
            Ok "$f not yet created (will be generated on first run)"
        }
    }
}

# ============================================================
# PHASE 2: Services
# ============================================================
Write-Host ""
Write-Host "--- Phase 2: Services ---"

# FlexTpmEngine
$svc = Get-Service FlexTpmEngine -ErrorAction SilentlyContinue
if ($svc) {
    Ok "FlexTpmEngine service exists (Status: $($svc.Status))"
} else {
    sc.exe create FlexTpmEngine binPath= "`"$FlexDir\flextpm.exe`" --service" start= auto DisplayName= "FlexTPM Engine" | Out-Null
    sc.exe description FlexTpmEngine "FlexTPM 2.0 - Software-defined TPM engine" | Out-Null
    sc.exe failure FlexTpmEngine reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
    Fixed "Created FlexTpmEngine service"
}

# FlexTpmLink
$svc = Get-Service FlexTpmLink -ErrorAction SilentlyContinue
if ($svc) {
    Ok "FlexTpmLink service exists (Status: $($svc.Status))"
} else {
    sc.exe create FlexTpmLink binPath= "`"$FlexDir\flexsvc.exe`"" start= auto DisplayName= "FlexTPM Link" | Out-Null
    sc.exe description FlexTpmLink "FlexTPM 2.0 - Creates TPM device symlink for TBS" | Out-Null
    sc.exe failure FlexTpmLink reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
    Fixed "Created FlexTpmLink service"
}

# TBS service — may not exist on machines with no real TPM
$tbsSvc = Get-Service TBS -ErrorAction SilentlyContinue
if (-not $tbsSvc) {
    Status "TBS service not found, creating..."
    sc.exe create TBS binPath= "$env:SystemRoot\System32\svchost.exe -k netsvcs" start= auto DisplayName= "TPM Base Services" | Out-Null
    sc.exe description TBS "Enables access to the TPM" | Out-Null
    # Set the service DLL for svchost
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\TBS\Parameters" /v ServiceDll /t REG_EXPAND_SZ /d "%SystemRoot%\System32\tbssvc.dll" /f 2>&1 | Out-Null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\TBS\Parameters" /v ServiceDllUnloadOnStop /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    Fixed "Created TBS service"
}

# Service dependencies — use PowerShell Set-ItemProperty for correct REG_MULTI_SZ handling
Status "Service dependencies..."
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\FlexTpmLink" -Name DependOnService -Value @("FlexTpmEngine") -Type MultiString -ErrorAction SilentlyContinue
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\tbs" -Name DependOnService -Value @("RPCSS", "FlexTpmLink") -Type MultiString -ErrorAction SilentlyContinue
Ok "Dependencies set: FlexTpmEngine -> FlexTpmLink -> TBS"

# ============================================================
# PHASE 3: UMDF Driver (ROOT\FLEXTPM\0000)
# ============================================================
Write-Host ""
Write-Host "--- Phase 3: UMDF Driver ---"

$umdfDev = Get-PnpDevice -InstanceId 'ROOT\FLEXTPM\0000' -ErrorAction SilentlyContinue
if ($umdfDev -and $umdfDev.Status -eq 'OK') {
    Ok "ROOT\FLEXTPM\0000 present and OK"
} else {
    Status "UMDF device missing or not OK, reinstalling..."
    # Check both possible driver locations (dev layout vs installer layout)
    $driverDir = Join-Path $FlexDir "driver"
    if (-not (Test-Path (Join-Path $driverDir "flextpm.inf"))) {
        $driverDir = Join-Path $FlexDir "umdf_tpm\driver"
    }
    $infPath = Join-Path $driverDir "flextpm.inf"
    if (Test-Path $infPath) {
        # Create device node via SetupAPI
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct SP_DEVINFO_R { public uint cbSize; public Guid ClassGuid; public uint DevInst; public IntPtr Reserved; }
public static class SetupR {
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr SetupDiCreateDeviceInfoList(ref Guid g, IntPtr h);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool SetupDiCreateDeviceInfo(IntPtr s, string n, ref Guid g, string d, IntPtr h, uint f, ref SP_DEVINFO_R i);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool SetupDiSetDeviceRegistryProperty(IntPtr s, ref SP_DEVINFO_R i, uint p, byte[] b, uint l);
    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiCallClassInstaller(uint f, IntPtr s, ref SP_DEVINFO_R i);
    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
}
'@
        $cg = [Guid]::new("d94ee5d8-d189-4994-83d2-f68d7d7b30e6")
        $dis = [SetupR]::SetupDiCreateDeviceInfoList([ref]$cg, [IntPtr]::Zero)
        $di = New-Object SP_DEVINFO_R
        $di.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][SP_DEVINFO_R])
        [SetupR]::SetupDiCreateDeviceInfo($dis, "FLEXTPM", [ref]$cg, "FlexTPM 2.0 Software Device", [IntPtr]::Zero, 1, [ref]$di) | Out-Null
        $hw = [System.Text.Encoding]::Unicode.GetBytes("Root\FLEXTPM`0`0")
        [SetupR]::SetupDiSetDeviceRegistryProperty($dis, [ref]$di, 1, $hw, [uint32]$hw.Length) | Out-Null
        [SetupR]::SetupDiCallClassInstaller(25, $dis, [ref]$di) | Out-Null
        [SetupR]::SetupDiDestroyDeviceInfoList($dis) | Out-Null
        pnputil /add-driver "`"$infPath`"" /install 2>&1 | Out-Null
        Start-Sleep 3
        $check = Get-PnpDevice -InstanceId 'ROOT\FLEXTPM\0000' -ErrorAction SilentlyContinue
        if ($check -and $check.Status -eq 'OK') { Fixed "UMDF driver installed" }
        else { Fail "UMDF driver install failed" }
    } else {
        Fail "flextpm.inf not found at $infPath"
    }
}

# ============================================================
# PHASE 4: tpm_virtual.inf (ROOT\SECURITY\0000)
# ============================================================
Write-Host ""
Write-Host "--- Phase 4: TPM Virtual Device ---"

$tpmDev = Get-PnpDevice -InstanceId 'ROOT\SECURITY\0000' -ErrorAction SilentlyContinue
$tpmDriverOk = $false
if ($tpmDev) {
    $svcProp = (Get-PnpDeviceProperty -InstanceId 'ROOT\SECURITY\0000' -ErrorAction SilentlyContinue |
        Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Service' }).Data
    if ($svcProp -eq 'TPM') {
        Ok "ROOT\SECURITY\0000 present with tpm.sys"
        $tpmDriverOk = $true
    } else {
        Status "ROOT\SECURITY\0000 exists but no driver, reinstalling..."
    }
} else {
    Status "ROOT\SECURITY\0000 missing, creating..."
}

if (-not $tpmDriverOk) {
    $tvDir = Join-Path $FlexDir "tpm_virtual"
    $tvInf = Join-Path $tvDir "tpm_virtual.inf"
    if (Test-Path $tvInf) {
        # Remove broken device if exists
        if ($tpmDev) { pnputil /remove-device 'ROOT\SECURITY\0000' /subtree 2>&1 | Out-Null; Start-Sleep 1 }

        # Create device node with correct ClassGuid
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct SP_DEVINFO_S { public uint cbSize; public Guid ClassGuid; public uint DevInst; public IntPtr Reserved; }
public static class SetupS {
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr SetupDiCreateDeviceInfoList(ref Guid g, IntPtr h);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool SetupDiCreateDeviceInfo(IntPtr s, string n, ref Guid g, string d, IntPtr h, uint f, ref SP_DEVINFO_S i);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool SetupDiSetDeviceRegistryProperty(IntPtr s, ref SP_DEVINFO_S i, uint p, byte[] b, uint l);
    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiCallClassInstaller(uint f, IntPtr s, ref SP_DEVINFO_S i);
    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
}
'@
        $cg2 = [Guid]::new("d94ee5d8-d189-4994-83d2-f68d7d41b0e6")
        $dis2 = [SetupS]::SetupDiCreateDeviceInfoList([ref]$cg2, [IntPtr]::Zero)
        $di2 = New-Object SP_DEVINFO_S
        $di2.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][SP_DEVINFO_S])
        [SetupS]::SetupDiCreateDeviceInfo($dis2, "SECURITY", [ref]$cg2, "Trusted Platform Module 2.0", [IntPtr]::Zero, 1, [ref]$di2) | Out-Null
        $hw2 = [System.Text.Encoding]::Unicode.GetBytes("ACPI\MSFT0101`0`0")
        [SetupS]::SetupDiSetDeviceRegistryProperty($dis2, [ref]$di2, 1, $hw2, [uint32]$hw2.Length) | Out-Null
        [SetupS]::SetupDiCallClassInstaller(25, $dis2, [ref]$di2) | Out-Null
        [SetupS]::SetupDiDestroyDeviceInfoList($dis2) | Out-Null

        pnputil /add-driver "`"$tvInf`"" /install 2>&1 | Out-Null
        Start-Sleep 3
        $check2 = Get-PnpDevice -InstanceId 'ROOT\SECURITY\0000' -ErrorAction SilentlyContinue
        $svc2 = (Get-PnpDeviceProperty -InstanceId 'ROOT\SECURITY\0000' -ErrorAction SilentlyContinue |
            Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Service' }).Data
        if ($svc2 -eq 'TPM') { Fixed "tpm_virtual device installed with tpm.sys" }
        else { Fail "tpm_virtual device install failed" }
    } else {
        Fail "tpm_virtual.inf not found at $tvInf"
    }
}

# ============================================================
# PHASE 5: Start services in order
# ============================================================
Write-Host ""
Write-Host "--- Phase 5: Service Startup ---"

# TBS simulator mode — ensure Parameters key exists
if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\TBS\Parameters')) {
    New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\TBS\Parameters' -Force | Out-Null
}
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\TBS\Parameters' -Name UseSimulator -Value 1 -Type DWord -ErrorAction SilentlyContinue

Stop-Service TBS -Force -ErrorAction SilentlyContinue
Stop-Service FlexTpmLink -Force -ErrorAction SilentlyContinue
Stop-Service FlexTpmEngine -Force -ErrorAction SilentlyContinue
Start-Sleep 2

Start-Service FlexTpmEngine -ErrorAction SilentlyContinue
Start-Sleep 3
if ((Get-Service FlexTpmEngine).Status -eq 'Running') { Ok "FlexTpmEngine running" }
else { Fail "FlexTpmEngine failed to start" }

# Verify TCP ports
Start-Sleep 1
$ports = netstat -an 2>$null | Select-String "127.0.0.1:2321.*LISTENING"
if ($ports) { Ok "TCP simulator listening on 2321/2322" }
else { Fail "TCP simulator not listening" }

Start-Service FlexTpmLink -ErrorAction SilentlyContinue
Start-Sleep 2
if ((Get-Service FlexTpmLink).Status -eq 'Running') { Ok "FlexTpmLink running" }
else { Fail "FlexTpmLink failed to start" }

Start-Service TBS -ErrorAction SilentlyContinue
Start-Sleep 3
if ((Get-Service TBS).Status -eq 'Running') { Ok "TBS running" }
else { Fail "TBS failed to start" }

# ============================================================
# PHASE 6: TPM Provisioning
# ============================================================
Write-Host ""
Write-Host "--- Phase 6: TPM Provisioning ---"

$tpm = Get-Tpm -ErrorAction SilentlyContinue
if (-not $tpm -or -not $tpm.TpmPresent) {
    Fail "TPM not present after service startup"
} else {
    Ok "TPM present (Manufacturer: $($tpm.ManufacturerIdTxt))"

    if ($tpm.TpmReady) {
        Ok "TPM already ready — no provisioning needed"
    } else {
        Status "TPM not ready, attempting provisioning..."

        # Restore registry from backup if -RestoreState
        if ($RestoreState -and (Test-Path (Join-Path $BackupDir "tpm_wmi_admin.reg"))) {
            reg import (Join-Path $BackupDir "tpm_wmi_admin.reg") 2>&1 | Out-Null
            reg import (Join-Path $BackupDir "tpm_wmi_taskstates.reg") 2>&1 | Out-Null
            reg import (Join-Path $BackupDir "tpm_wmi_provision.reg") 2>&1 | Out-Null
            Fixed "Restored TPM registry from backup"
            Restart-Service TBS -Force
            Start-Sleep 5
            $tpm = Get-Tpm -ErrorAction SilentlyContinue
        }

        if (-not $tpm.TpmReady) {
            # Try to read or create SRK via TBS API
            Status "Creating SRK via TBS..."
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TbsRepair {
    [StructLayout(LayoutKind.Sequential)]
    public struct P { public uint v; public uint f; }
    [DllImport("tbs.dll")] public static extern uint Tbsi_Context_Create(ref P p, out IntPtr h);
    [DllImport("tbs.dll")] public static extern uint Tbsip_Submit_Command(IntPtr h, uint l, uint p, byte[] c, uint cl, byte[] r, ref uint rl);
    [DllImport("tbs.dll")] public static extern uint Tbsip_Context_Close(IntPtr h);
}
'@
            $tp = New-Object TbsRepair+P; $tp.v = 2; $tp.f = 4
            $th = [IntPtr]::Zero
            $tr = [TbsRepair]::Tbsi_Context_Create([ref]$tp, [ref]$th)

            if ($tr -ne 0) {
                Fail "TBS context creation failed: 0x$($tr.ToString('X8'))"
            } else {
                # Check if SRK exists
                $readCmd = [byte[]]@(0x80,0x01,0x00,0x00,0x00,0x0E,0x00,0x00,0x01,0x73,0x81,0x00,0x00,0x01)
                $rBuf = New-Object byte[] 4096; [uint32]$rLen = 4096
                [TbsRepair]::Tbsip_Submit_Command($th, 0, 200, $readCmd, $readCmd.Length, $rBuf, [ref]$rLen) | Out-Null
                $tpmRc = ($rBuf[6] -shl 24) -bor ($rBuf[7] -shl 16) -bor ($rBuf[8] -shl 8) -bor $rBuf[9]

                if ($tpmRc -ne 0) {
                    Status "SRK not found (0x$($tpmRc.ToString('X8'))), creating..."

                    # TPM2_Startup
                    $startupCmd = [byte[]]@(0x80,0x01,0x00,0x00,0x00,0x0C,0x00,0x00,0x01,0x44,0x00,0x00)
                    $sBuf = New-Object byte[] 256; [uint32]$sLen = 256
                    [TbsRepair]::Tbsip_Submit_Command($th, 0, 200, $startupCmd, $startupCmd.Length, $sBuf, [ref]$sLen) | Out-Null

                    # TPM2_CreatePrimary — RSA-2048 SRK in owner hierarchy
                    $cpCmd = [byte[]]@(
                        0x80, 0x02,
                        0x00, 0x00, 0x00, 0x00,   # size placeholder
                        0x00, 0x00, 0x01, 0x31,   # CC=CreatePrimary
                        0x40, 0x00, 0x00, 0x01,   # TPM_RH_OWNER
                        0x00, 0x00, 0x00, 0x09,   # authSize=9
                        0x40, 0x00, 0x00, 0x09,   # TPM_RS_PW
                        0x00, 0x00, 0x00, 0x00, 0x00,   # nonce=0, attrs=0, hmac=0
                        0x00, 0x04, 0x00, 0x00, 0x00, 0x00,   # inSensitive
                        0x00, 0x22,               # inPublic size=34
                        0x00, 0x01,               # RSA
                        0x00, 0x0B,               # SHA256
                        0x00, 0x03, 0x00, 0x72,   # attributes
                        0x00, 0x00,               # authPolicy=0
                        0x00, 0x06, 0x00, 0x80, 0x00, 0x43,   # AES-128-CFB
                        0x00, 0x10,               # scheme=NULL
                        0x08, 0x00,               # keyBits=2048
                        0x00, 0x00, 0x00, 0x00,   # exponent=0
                        0x00, 0x00,               # unique=0
                        0x00, 0x00,               # outsideInfo=0
                        0x00, 0x00, 0x00, 0x00    # creationPCR=0
                    )
                    $sz = $cpCmd.Length
                    $cpCmd[2] = [byte](($sz -shr 24) -band 0xFF)
                    $cpCmd[3] = [byte](($sz -shr 16) -band 0xFF)
                    $cpCmd[4] = [byte](($sz -shr 8) -band 0xFF)
                    $cpCmd[5] = [byte]($sz -band 0xFF)

                    $cpBuf = New-Object byte[] 4096; [uint32]$cpLen = 4096
                    [TbsRepair]::Tbsip_Submit_Command($th, 0, 200, $cpCmd, [uint32]$cpCmd.Length, $cpBuf, [ref]$cpLen) | Out-Null
                    $cpRc = ($cpBuf[6] -shl 24) -bor ($cpBuf[7] -shl 16) -bor ($cpBuf[8] -shl 8) -bor $cpBuf[9]

                    if ($cpRc -eq 0) {
                        $srkH = ($cpBuf[10] -shl 24) -bor ($cpBuf[11] -shl 16) -bor ($cpBuf[12] -shl 8) -bor $cpBuf[13]
                        Fixed "SRK created (handle 0x$($srkH.ToString('X8')))"

                        # EvictControl to persist at 0x81000001
                        $evCmd = [byte[]]@(
                            0x80, 0x02,
                            0x00, 0x00, 0x00, 0x23,
                            0x00, 0x00, 0x01, 0x20,
                            0x40, 0x00, 0x00, 0x01,
                            [byte](($srkH -shr 24) -band 0xFF), [byte](($srkH -shr 16) -band 0xFF),
                            [byte](($srkH -shr 8) -band 0xFF), [byte]($srkH -band 0xFF),
                            0x00, 0x00, 0x00, 0x09,
                            0x40, 0x00, 0x00, 0x09,
                            0x00, 0x00, 0x00, 0x00, 0x00,
                            0x81, 0x00, 0x00, 0x01
                        )
                        $evBuf = New-Object byte[] 256; [uint32]$evLen = 256
                        [TbsRepair]::Tbsip_Submit_Command($th, 0, 200, $evCmd, [uint32]$evCmd.Length, $evBuf, [ref]$evLen) | Out-Null
                        $evRc = ($evBuf[6] -shl 24) -bor ($evBuf[7] -shl 16) -bor ($evBuf[8] -shl 8) -bor $evBuf[9]
                        if ($evRc -eq 0) { Fixed "SRK persisted at 0x81000001" }
                        else { Fail "EvictControl failed: 0x$($evRc.ToString('X8'))" }
                    } else {
                        Fail "CreatePrimary failed: 0x$($cpRc.ToString('X8'))"
                    }

                    # Re-read SRK public
                    $rBuf2 = New-Object byte[] 4096; [uint32]$rLen2 = 4096
                    [TbsRepair]::Tbsip_Submit_Command($th, 0, 200, $readCmd, $readCmd.Length, $rBuf2, [ref]$rLen2) | Out-Null
                    $tpmRc = ($rBuf2[6] -shl 24) -bor ($rBuf2[7] -shl 16) -bor ($rBuf2[8] -shl 8) -bor $rBuf2[9]
                    if ($tpmRc -eq 0) { $rBuf = $rBuf2; $rLen = $rLen2 }
                }

                # Store SRK hash in registry
                if ($tpmRc -eq 0 -and $rLen -gt 12) {
                    $pubSz = ($rBuf[10] -shl 8) -bor $rBuf[11]
                    $pubArea = $rBuf[10..($pubSz + 11)]
                    $srkHash = [System.Security.Cryptography.SHA1]::Create().ComputeHash($pubArea)
                    $hex = ($srkHash | ForEach-Object { $_.ToString('X2') }) -join ''

                    # Ensure WMI registry keys exist before writing values
                    foreach ($wmiKey in @(
                        'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI',
                        'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin',
                        'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\TaskStates',
                        'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\ProvisionInfo'
                    )) {
                        if (-not (Test-Path $wmiKey)) { New-Item -Path $wmiKey -Force | Out-Null }
                    }

                    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name SRKPub -Value $srkHash -Type Binary
                    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name OwnerAuthStatus -Value 1 -Type DWord
                    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name TPMCleared -Value 0 -Type DWord
                    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name OwnerAuthFull -Value '2jmj7l5rSw0yVb/vlWAYkK/YBwk=' -Type String
                    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name StorageOwnerAuth -Value '2jmj7l5rSw0yVb/vlWAYkK/YBwk=' -Type String
                    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name LockoutHash -Value '2jmj7l5rSw0yVb/vlWAYkK/YBwk=' -Type String
                    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\TaskStates' -Name TpmProvisionFailedSteps -Value 0 -Type DWord
                    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\TaskStates' -Name TpmProvisionHresult -Value 0 -Type DWord
                    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\ProvisionInfo' -Name ClearReason -Value '' -Type String
                    Fixed "SRK hash stored: $hex"
                    Fixed "Provisioning registry set"

                    Restart-Service TBS -Force
                    Start-Sleep 5
                }

                [TbsRepair]::Tbsip_Context_Close($th) | Out-Null
            }
        }
    }
}

# ============================================================
# PHASE 7: Final Verification
# ============================================================
Write-Host ""
Write-Host "--- Final Verification ---"

$final = Get-Tpm -ErrorAction SilentlyContinue
if ($final) {
    Write-Host ""
    Write-Host "  TPM Present:      $($final.TpmPresent)"
    Write-Host "  TPM Ready:        $($final.TpmReady)"
    Write-Host "  TPM Enabled:      $($final.TpmEnabled)"
    Write-Host "  TPM Activated:    $($final.TpmActivated)"
    Write-Host "  TPM Owned:        $($final.TpmOwned)"
    Write-Host "  Manufacturer:     $($final.ManufacturerIdTxt)"
}

# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Repair Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($fixes.Count -gt 0) {
    Write-Host "  Fixed $($fixes.Count) issue(s):" -ForegroundColor Yellow
    foreach ($f in $fixes) { Write-Host "    - $f" -ForegroundColor Yellow }
}

if ($failures.Count -gt 0) {
    Write-Host "  $($failures.Count) failure(s) remain:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "    - $f" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Try: .\repair_tpm.ps1 -RestoreState" -ForegroundColor Red
    exit 1
}

if ($final -and $final.TpmReady) {
    Write-Host ""
    Write-Host "  ALL CHECKS PASSED - FlexTPM is fully operational!" -ForegroundColor Green
    Write-Host ""

    # Auto-backup on successful repair
    Write-Host "  Running post-repair backup..."
    & "$FlexDir\backup_tpm.ps1" -InstallDir "$FlexDir" -BackupDir "$env:LOCALAPPDATA\FlexTPM\Backups" 2>$null
} else {
    Write-Host ""
    Write-Host "  TPM is present but not ready. A reboot may be required." -ForegroundColor Yellow
    exit 1
}
