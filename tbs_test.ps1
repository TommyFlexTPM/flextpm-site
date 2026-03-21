Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class TbsX {
    [StructLayout(LayoutKind.Sequential)]
    public struct P { public uint v; public uint f; }
    [DllImport("tbs.dll")] public static extern uint Tbsi_Context_Create(ref P p, out IntPtr h);
    [DllImport("tbs.dll")] public static extern uint Tbsip_Submit_Command(IntPtr h, uint l, uint p, byte[] c, uint cl, byte[] r, ref uint rl);
    [DllImport("tbs.dll")] public static extern uint Tbsip_Context_Close(IntPtr h);
}
"@

Write-Host "1. Creating TBS context..." -Fore Yellow
$p = New-Object TbsX+P; $p.v = 2; $p.f = 4
$ctx = [IntPtr]::Zero
$rc = [TbsX]::Tbsi_Context_Create([ref]$p, [ref]$ctx)
Write-Host "   Result: 0x$($rc.ToString('X8'))" -Fore $(if($rc -eq 0){'Green'}else{'Red'})

if ($rc -eq 0) {
    Write-Host "2. Getting manufacturer..." -Fore Yellow
    $cmd = [byte[]]@(0x80,0x01,0x00,0x00,0x00,0x16,0x00,0x00,0x01,0x7A,0x00,0x00,0x00,0x06,0x00,0x00,0x01,0x05,0x00,0x00,0x00,0x01)
    $resp = New-Object byte[] 4096; [uint32]$rl = 4096
    [TbsX]::Tbsip_Submit_Command($ctx, 0, 200, $cmd, [uint32]$cmd.Length, $resp, [ref]$rl) | Out-Null
    $tpmRc = ($resp[6] -shl 24) -bor ($resp[7] -shl 16) -bor ($resp[8] -shl 8) -bor $resp[9]
    if ($tpmRc -eq 0 -and $rl -gt 20) {
        $mfr = [System.Text.Encoding]::ASCII.GetString($resp, 23, 4)
        Write-Host "   Manufacturer: $mfr" -Fore Green
        Write-Host "   TPM IS WORKING!" -Fore Green
    } else {
        Write-Host "   TPM RC: 0x$($tpmRc.ToString('X8'))" -Fore Red
    }

    Write-Host "3. Checking SRK..." -Fore Yellow
    $srkCmd = [byte[]]@(0x80,0x01,0x00,0x00,0x00,0x0E,0x00,0x00,0x01,0x73,0x81,0x00,0x00,0x01)
    $srkBuf = New-Object byte[] 4096; [uint32]$srkLen = 4096
    [TbsX]::Tbsip_Submit_Command($ctx, 0, 200, $srkCmd, [uint32]$srkCmd.Length, $srkBuf, [ref]$srkLen) | Out-Null
    $srkRc = ($srkBuf[6] -shl 24) -bor ($srkBuf[7] -shl 16) -bor ($srkBuf[8] -shl 8) -bor $srkBuf[9]
    if ($srkRc -eq 0) { Write-Host "   SRK: Present" -Fore Green }
    else { Write-Host "   SRK: Missing (0x$($srkRc.ToString('X8')))" -Fore Yellow }

    [TbsX]::Tbsip_Context_Close($ctx) | Out-Null
} else {
    Write-Host "TBS CANNOT FIND TPM" -Fore Red
}

Write-Host ""
Write-Host "4. Get-Tpm:" -Fore Yellow
try { Get-Tpm | Format-List } catch { Write-Host "   $($_.Exception.Message)" -Fore Red }
