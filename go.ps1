# Override Get-Tpm RIGHT NOW in this session
function global:Get-Tpm {
    $t = Get-WmiObject -Namespace "root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm
    [PSCustomObject]@{
        TpmPresent = $true
        TpmReady = [bool]$t.IsEnabled_InitialValue -and [bool]$t.IsActivated_InitialValue -and [bool]$t.IsOwned_InitialValue
        TpmEnabled = [bool]$t.IsEnabled_InitialValue
        TpmActivated = [bool]$t.IsActivated_InitialValue
        TpmOwned = [bool]$t.IsOwned_InitialValue
        ManufacturerIdTxt = $t.ManufacturerIdTxt
        ManufacturerVersion = $t.ManufacturerVersion
    }
}
Write-Host "Get-Tpm override installed" -Fore Green
Get-Tpm | Format-List
