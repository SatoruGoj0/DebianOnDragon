<#
.SYNOPSIS
Copies the Lenovo 83N3 device-signed Qualcomm firmware out of the Windows
DriverStore into a folder (for example on a USB stick), for use with
debondragon-firmware on Linux. Read-only on the Windows side.

.EXAMPLE
.\Export-Firmware.ps1 -Destination E:\debondragon-firmware
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
$store = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
$files = 'qcadsp8380.mbn', 'adsp_dtbs.elf', 'qccdsp8380.mbn', 'cdsp_dtbs.elf',
         'qcdxkmsucpurwa.mbn', 'battmgr.jsn', 'adspr.jsn', 'adspua.jsn', 'cdspr.jsn'

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
foreach ($name in $files) {
    # DriverStore keeps older driver versions side by side; take the newest.
    $found = Get-ChildItem -Path $store -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($found) {
        Copy-Item -LiteralPath $found.FullName -Destination (Join-Path $Destination $name) -Force
        "copied  $name  ($($found.Directory.Name))"
    } else {
        "MISSING $name"
    }
}
"Done. In Linux run: sudo debondragon-firmware <this folder>"
