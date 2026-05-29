#Requires -Version 7.0
<#
.SYNOPSIS
    [DUMMY] Next-stage processor — receives a manifest of moved files and acts on them.

.DESCRIPTION
    This is a placeholder script. Replace the body of the "Do work here" section
    with your actual processing logic.

    Called by Sync-AndMove.ps1 with:
        pwsh -NonInteractive -File Process-Files.ps1 -ManifestPath <path>

    CONTRACT:
        - Read the file list from $ManifestPath.
        - Do your work on each file.
        - Delete $ManifestPath when ALL work is successfully complete.
          Leaving the manifest behind signals to Sync-AndMove.ps1 that this
          script did not finish, blocking new batches until resolved.

.PARAMETER ManifestPath
    Full path to the moved_files_<timestamp>.txt manifest written by Sync-AndMove.ps1.
#>

param(
    [Parameter(Mandatory)]
    [string]$ManifestPath
)

Import-Module .\Invoke-WindowsToastNotification.psm1 -Function Invoke-WindowsToastNotification

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SCRIPT_DIR = $PSScriptRoot

# ── Logging helper ───────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path (Join-Path $SCRIPT_DIR "Process-Files.log") -Value $line
}

# ── Validate manifest ─────────────────────────
if (-not (Test-Path $ManifestPath)) {
    Write-Log "Manifest not found: '$ManifestPath'" "ERROR"
    exit 1
}

$files = @(Get-Content $ManifestPath | Where-Object { $_ -match '\S' })

if ($files.Count -eq 0) {
    Write-Log "Manifest '$ManifestPath' is empty — nothing to process." "WARN"
    Remove-Item $ManifestPath -Force
    exit 0
}

Write-Log "=== Process-Files started ==="
Write-Log "Manifest : $ManifestPath"
Write-Log "Files    : $($files.Count)"

# ════════════════════════════════════════════
#  DO WORK HERE
#  $files is a string array of fully-qualified destination paths.
#  Replace the block below with your real logic.
# ════════════════════════════════════════════
$magickLocation = "E:\Softwares\ImageMagick\ImageMagick-7.1.2-21-portable-Q16-HDRI-x64\magick.exe"
$outputDirectory = "Z:\Test-folder\"

foreach ($filePath in $files) {
    if (-not (Test-Path $filePath)) {
        Write-Log "  [SKIP] File not found (may have been manually moved): $filePath" "WARN"
        continue
    }

    $destinationFilename = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    $destinationFile = Join-Path $outputDirectory ($destinationFilename + ".jxl")

    Write-Log "  Converting: $filePath → $destinationFile"
    & $magickLocation "$filePath" "$destinationFile"
}
# ════════════════════════════════════════════

# ── Delete manifest only after ALL work is done ──
# If an exception is thrown above, this line is never reached, the manifest
# survives, and Sync-AndMove.ps1 will detect and block further batches.
try {
    Remove-Item $ManifestPath -Force
    Write-Log "Manifest deleted: $ManifestPath"
}
catch {
    Write-Log "Could not delete manifest '$ManifestPath': $_" "ERROR"
    Invoke-WindowsToastNotification -AppId "Microsoft.PowerShell_8wekyb3d8bbwe!App" `
    -Title "Syncthing" `
    -Detail "Syncthing post transfer process" `
    -Sound Alarm `
    -Message "Something went wrong. Check the logs."
    exit 1
}

Write-Log "=== Process-Files complete ==="
    Invoke-WindowsToastNotification -AppId "Microsoft.PowerShell_8wekyb3d8bbwe!App" `
    -Title "Syncthing" `
    -Detail "Syncthing post transfer process" `
    -Sound Alarm `
    -Message "Post processing completed."