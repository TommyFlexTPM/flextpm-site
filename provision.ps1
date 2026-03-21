Write-Host "=== Fixing Get-Tpm ===" -Fore Cyan

# Find the old Mac's Microsoft.Tpm.Commands.dll in GAC
$gacPath = "$env:SystemRoot\Microsoft.Net\assembly\GAC_64\Microsoft.Tpm.Commands"
$current = Get-ChildItem $gacPath -Filter "Microsoft.Tpm.Commands.dll" -Recurse -EA SilentlyContinue | Select -First 1

if ($current) {
    Write-Host "Current: $($current.FullName) ($($current.Length) bytes)" -Fore Yellow
    
    # Download the working version from the main machine (build 26100)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $dest = $current.FullName
    
    # Backup first
    $backup = "$dest.bak"
    if (-not (Test-Path $backup)) {
        Copy-Item $dest $backup -Force
        Write-Host "Backed up to .bak" -Fore Green
    }
    
    Invoke-WebRequest 'https://flextpm.com/Microsoft.Tpm.Commands.dll' -OutFile $dest
    Write-Host "Replaced with working version" -Fore Green
} else {
    Write-Host "Microsoft.Tpm.Commands.dll not found in GAC" -Fore Red
}

Write-Host "`n=== Get-Tpm ===" -Fore Cyan
try { Get-Tpm | Format-List TpmPresent, TpmReady, ManufacturerIdTxt } catch { Write-Host $_.Exception.Message -Fore Red }
