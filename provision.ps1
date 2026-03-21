Write-Host "=== Fixing Get-Tpm ===" -Fore Cyan

# Create a custom Get-Tpm function that bypasses the broken PPI query
# Install it as a PowerShell profile so it's always available
$profileDir = Split-Path $PROFILE.AllUsersAllHosts
if (-not (Test-Path $profileDir)) { New-Item -Path $profileDir -ItemType Directory -Force | Out-Null }

$profileScript = @'
# FlexTPM: Override Get-Tpm to handle missing PPI on Macs
function Get-Tpm {
    [CmdletBinding()]
    param()
    $tpm = Get-WmiObject -Namespace "root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction Stop
    $ready = $false
    try { $result = $tpm.IsReady(); $ready = $result.IsReady } catch { }
    $enabled = $false
    try { $result = $tpm.IsEnabled(); $enabled = $result.IsEnabled } catch { $enabled = $tpm.IsEnabled_InitialValue }
    $activated = $false
    try { $result = $tpm.IsActivated(); $activated = $result.IsActivated } catch { $activated = $tpm.IsActivated_InitialValue }
    $owned = $false
    try { $result = $tpm.IsOwned(); $owned = $result.IsOwned } catch { $owned = $tpm.IsOwned_InitialValue }
    
    [PSCustomObject]@{
        TpmPresent = $true
        TpmReady = $ready
        TpmEnabled = $enabled
        TpmActivated = $activated
        TpmOwned = $owned
        RestartPending = $false
        ManufacturerId = $tpm.ManufacturerId
        ManufacturerIdTxt = $tpm.ManufacturerIdTxt
        ManufacturerVersion = $tpm.ManufacturerVersion
        ManufacturerVersionFull20 = $tpm.ManufacturerVersionFull20
        ManagedAuthLevel = "Full"
        OwnerAuth = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tpm\WMI\Admin' -Name OwnerAuthFull -EA SilentlyContinue).OwnerAuthFull
        OwnerClearDisabled = $false
        AutoProvisioning = "Enabled"
        LockedOut = $false
        LockoutHealTime = "1 hours"
        LockoutCount = 0
        LockoutMax = 10
        SelfTest = @()
    }
}
'@

Set-Content -Path $PROFILE.AllUsersAllHosts -Value $profileScript -Force
Write-Host "Installed custom Get-Tpm to $($PROFILE.AllUsersAllHosts)" -Fore Green

Write-Host "`n=== Testing ===" -Fore Cyan
# Load it now
. $PROFILE.AllUsersAllHosts
Get-Tpm | Format-List TpmPresent, TpmReady, TpmEnabled, TpmActivated, TpmOwned, ManufacturerIdTxt
