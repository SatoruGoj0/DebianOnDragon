<#
.SYNOPSIS
Registers the installed Debian GRUB as a UEFI boot entry, from Windows.

.DESCRIPTION
On the 83N3, Linux v7.2 cannot write UEFI variables (QSEECOM is not enabled
for this machine: "qseecom: untested machine, skipping"), so the installer
puts GRUB on the EFI partition but cannot create its boot entry. Windows can.

Without -Apply this only reports: it temporarily assigns drive letters to
the internal EFI system partitions, looks for \EFI\debian\grubaa64.efi,
lists the firmware boot entries, removes the letters again and writes a
report next to this script. With -Apply it also creates a "debian" firmware
boot entry for that GRUB and puts it first in the boot order. Windows Boot
Manager stays in the list (and GRUB offers Windows in its menu).

Run from an elevated PowerShell:
  powershell -ExecutionPolicy Bypass -File .\Add-DebianBootEntry.ps1
  powershell -ExecutionPolicy Bypass -File .\Add-DebianBootEntry.ps1 -Apply
#>
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$report = Join-Path $PSScriptRoot ("boot-entry-report-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $report | Out-Null

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run this from an administrator PowerShell." -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}

$esps = Get-Partition -DiskNumber 0 | Where-Object GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$free = [char[]]([int][char]'R'..[int][char]'Y') | Where-Object { -not (Test-Path "$($_):\") }
$assigned = @()
$found = $null

function Invoke-Diskpart([string[]]$lines) {
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $lines -Encoding ascii
    diskpart /s $tmp | Out-Null
    Remove-Item $tmp
}

try {
    $i = 0
    foreach ($p in $esps) {
        $letter = $free[$i]; $i++
        Invoke-Diskpart @('select disk 0', "select partition $($p.PartitionNumber)", "assign letter=$letter")
        $assigned += [pscustomobject]@{ Partition = $p.PartitionNumber; Letter = $letter }
        Write-Host ("== EFI partition {0} ({1:N2} GB) as {2}:" -f $p.PartitionNumber, ($p.Size / 1GB), $letter)
        if (Test-Path "$($letter):\EFI") {
            Get-ChildItem "$($letter):\EFI" -Recurse -File -Include *.efi | ForEach-Object {
                "   {0}  {1:N0} bytes" -f $_.FullName.Substring(2), $_.Length
            }
        } else {
            Write-Host "   (no \EFI folder)"
        }
        if (-not $found -and (Test-Path "$($letter):\EFI\debian\grubaa64.efi")) {
            $found = [pscustomobject]@{ Partition = $p.PartitionNumber; Letter = $letter }
        }
    }

    Write-Host "`n== Firmware boot entries (before)"
    bcdedit /enum firmware | Select-String -Pattern '^(identifier|description|path|device|displayorder)|^\s+\{' | ForEach-Object { $_.Line }

    if (-not $found) {
        Write-Host "`nNo \EFI\debian\grubaa64.efi found on any internal EFI partition." -ForegroundColor Yellow
        Write-Host "GRUB was not installed; nothing changed."
    } elseif (-not $Apply) {
        Write-Host ("`nFound GRUB on EFI partition {0}. Re-run with -Apply to add the boot entry." -f $found.Partition) -ForegroundColor Green
    } else {
        $copy = bcdedit /copy '{bootmgr}' /d 'debian'
        $guid = [regex]::Match(($copy -join ' '), '\{[0-9a-fA-F-]{36}\}').Value
        if (-not $guid) { throw "bcdedit /copy failed: $copy" }
        bcdedit /set $guid device "partition=$($found.Letter):" | Out-Null
        bcdedit /set $guid path '\EFI\debian\grubaa64.efi' | Out-Null
        bcdedit /set '{fwbootmgr}' displayorder $guid /addfirst | Out-Null
        Write-Host "`nCreated firmware entry $guid -> \EFI\debian\grubaa64.efi (partition $($found.Partition)), first in boot order." -ForegroundColor Green
        Write-Host "`n== Firmware boot entries (after)"
        bcdedit /enum firmware | Select-String -Pattern '^(identifier|description|path|device|displayorder)|^\s+\{' | ForEach-Object { $_.Line }
    }
} finally {
    foreach ($a in $assigned) {
        Invoke-Diskpart @('select disk 0', "select partition $($a.Partition)", "remove letter=$($a.Letter)")
    }
    Stop-Transcript | Out-Null
    Write-Host "`nReport saved: $report"
}
