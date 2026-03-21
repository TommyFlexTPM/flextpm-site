Write-Host "=== FlexTPM Provisioning ===" -Fore Cyan

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class TbsProv {
    [StructLayout(LayoutKind.Sequential)]
    public struct P { public uint v; public uint f; }
    [DllImport("tbs.dll")] public static extern uint Tbsi_Context_Create(ref P p, out IntPtr h);
    [DllImport("tbs.dll")] public static extern uint Tbsip_Submit_Command(IntPtr h, uint l, uint p, byte[] c, uint cl, byte[] r, ref uint rl);
    [DllImport("tbs.dll")] public static extern uint Tbsip_Context_Close(IntPtr h);
}
"@

$p = New-Object TbsProv+P; $p.v = 2; $p.f = 4
$ctx = [IntPtr]::Zero
$rc = [TbsProv]::Tbsi_Context_Create([ref]$p, [ref]$ctx)
if ($rc -ne 0) { Write-Host "TBS failed: 0x$($rc.ToString('X8'))" -Fore Red; exit 1 }
Write-Host "TBS connected" -Fore Green

# Check SRK
Write-Host "`nChecking SRK..." -Fore Yellow
$readCmd = [byte[]]@(0x80,0x01,0x00,0x00,0x00,0x0E,0x00,0x00,0x01,0x73,0x81,0x00,0x00,0x01)
$rBuf = New-Object byte[] 4096; [uint32]$rLen = 4096
[TbsProv]::Tbsip_Submit_Command($ctx, 0, 200, $readCmd, [uint32]$readCmd.Length, $rBuf, [ref]$rLen) | Out-Null
$srkRc = ($rBuf[6] -shl 24) -bor ($rBuf[7] -shl 16) -bor ($rBuf[8] -shl 8) -bor $rBuf[9]

if ($srkRc -ne 0) {
    Write-Host "SRK missing, creating..." -Fore Yellow

    # TPM2_CreatePrimary — RSA-2048 SRK in owner hierarchy
    $cpCmd = [byte[]]@(
        0x80, 0x02,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x31,
        0x40, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x09,
        0x40, 0x00, 0x00, 0x09,
        0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x04, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x22,
        0x00, 0x01,
        0x00, 0x0B,
        0x00, 0x03, 0x00, 0x72,
        0x00, 0x00,
        0x00, 0x06, 0x00, 0x80, 0x00, 0x43,
        0x00, 0x10,
        0x08, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    )
    $sz = $cpCmd.Length
    $cpCmd[2] = [byte](($sz -shr 24) -band 0xFF)
    $cpCmd[3] = [byte](($sz -shr 16) -band 0xFF)
    $cpCmd[4] = [byte](($sz -shr 8) -band 0xFF)
    $cpCmd[5] = [byte]($sz -band 0xFF)

    $cpBuf = New-Object byte[] 4096; [uint32]$cpLen = 4096
    [TbsProv]::Tbsip_Submit_Command($ctx, 0, 200, $cpCmd, [uint32]$cpCmd.Length, $cpBuf, [ref]$cpLen) | Out-Null
    $cpRc = ($cpBuf[6] -shl 24) -bor ($cpBuf[7] -shl 16) -bor ($cpBuf[8] -shl 8) -bor $cpBuf[9]

    if ($cpRc -eq 0) {
        $srkH = ($cpBuf[10] -shl 24) -bor ($cpBuf[11] -shl 16) -bor ($cpBuf[12] -shl 8) -bor $cpBuf[13]
        Write-Host "SRK created: handle 0x$($srkH.ToString('X8'))" -Fore Green

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
        [TbsProv]::Tbsip_Submit_Command($ctx, 0, 200, $evCmd, [uint32]$evCmd.Length, $evBuf, [ref]$evLen) | Out-Null
        $evRc = ($evBuf[6] -shl 24) -bor ($evBuf[7] -shl 16) -bor ($evBuf[8] -shl 8) -bor $evBuf[9]
        if ($evRc -eq 0) { Write-Host "SRK persisted at 0x81000001" -Fore Green }
        else { Write-Host "EvictControl failed: 0x$($evRc.ToString('X8'))" -Fore Red }

        # Re-read SRK public for hash
        $rBuf2 = New-Object byte[] 4096; [uint32]$rLen2 = 4096
        [TbsProv]::Tbsip_Submit_Command($ctx, 0, 200, $readCmd, [uint32]$readCmd.Length, $rBuf2, [ref]$rLen2) | Out-Null
        $rBuf = $rBuf2; $rLen = $rLen2
        $srkRc = 0
    } else {
        Write-Host "CreatePrimary failed: 0x$($cpRc.ToString('X8'))" -Fore Red
    }
} else {
    Write-Host "SRK already exists" -Fore Green
}

# Set WMI registry
Write-Host "`nSetting WMI registry..." -Fore Yellow
foreach ($key in @(
    'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI',
    'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin',
    'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\TaskStates',
    'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\ProvisionInfo'
)) {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
}

# Store SRK hash if available
if ($srkRc -eq 0 -and $rLen -gt 12) {
    $pubSz = ($rBuf[10] -shl 8) -bor $rBuf[11]
    $pubArea = $rBuf[10..($pubSz + 11)]
    $srkHash = [System.Security.Cryptography.SHA1]::Create().ComputeHash($pubArea)
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name SRKPub -Value $srkHash -Type Binary
    Write-Host "SRK hash stored" -Fore Green
}

Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name OwnerAuthStatus -Value 1 -Type DWord
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name TPMCleared -Value 0 -Type DWord
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name OwnerAuthFull -Value '2jmj7l5rSw0yVb/vlWAYkK/YBwk=' -Type String
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name StorageOwnerAuth -Value '2jmj7l5rSw0yVb/vlWAYkK/YBwk=' -Type String
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name LockoutHash -Value '2jmj7l5rSw0yVb/vlWAYkK/YBwk=' -Type String
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\TaskStates' -Name TpmProvisionFailedSteps -Value 0 -Type DWord
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\TaskStates' -Name TpmProvisionHresult -Value 0 -Type DWord
Write-Host "WMI registry set" -Fore Green

[TbsProv]::Tbsip_Context_Close($ctx) | Out-Null

# Restart TBS to pick up new WMI state
Write-Host "`nRestarting TBS..." -Fore Yellow
Restart-Service TBS -Force
Start-Sleep 5

Write-Host "`n=== Get-Tpm ===" -Fore Cyan
try { Get-Tpm | Format-List TpmPresent, TpmReady, ManufacturerIdTxt } catch { Write-Host $_.Exception.Message -Fore Red }
