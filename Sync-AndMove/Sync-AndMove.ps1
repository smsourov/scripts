<#
.SYNOPSIS
    Watches Syncthing folder(s) via REST API and moves top-level files to a
    target directory once all transfers are idle.

.DESCRIPTION
    Reads watched folder IDs from  watch_list.txt  and the destination from
    targetfolder.txt  (both located next to this script).  Polls the
    Syncthing REST API every few seconds; when every watched folder reports
    state = "idle" the top-level files are moved to the target directory.

    After a successful move batch, a timestamped  moved_files_<ts>.txt  manifest
    is written and the next-stage script (Process-Files.ps1) is invoked with the
    manifest path as an argument.  If a previous manifest is found on startup
    (indicating the next-stage script was killed mid-run), the user is warned and
    the stale manifest is left for manual review before new batches are processed.

.NOTES
    Tested on PowerShell 7 + Syncthing v1.x
    Schedule with Task Scheduler:  pwsh.exe -File "C:\path\Sync-AndMove.ps1"
#>

#Requires -Version 7.0

# ─────────────────────────────────────────────
#  CONFIG  (edit these if your Syncthing setup differs)
# ─────────────────────────────────────────────
$ST_BASE_URL     = "http://127.0.0.1:8384"   # Syncthing GUI/API address
$ST_API_KEY      = "N4DffgFXQFgMe5FX7NdfufEwucb7UiAX"                         # Paste your API key here (GUI → Actions → Settings → API Key)
$POLL_SECONDS    = 10                         # How often to poll the API (seconds)
$SCRIPT_DIR      = $PSScriptRoot              # Config/manifest files live next to this script
$NEXT_SCRIPT          = Join-Path $SCRIPT_DIR "Process-Files.ps1"   # Next-stage script to invoke
$ENABLE_MOVE     = $false   # Set to $false to skip moving files; post-processing will still run on files in-place
# ─────────────────────────────────────────────

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Logging helper ───────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path (Join-Path $SCRIPT_DIR "Sync-AndMove.log") -Value $line
}

# ── Validate API key ─────────────────────────
if ([string]::IsNullOrWhiteSpace($ST_API_KEY)) {
    Write-Log "ST_API_KEY is empty. Open this script and paste your Syncthing API key." "ERROR"
    exit 1
}

# ── watch_list.txt ───────────────────────────
$watchListPath = Join-Path $SCRIPT_DIR "watch_list.txt"

if (-not (Test-Path $watchListPath)) {
    @(
        "# Syncthing Folder Watch List",
        "# Add one Syncthing folder ID per line below this comment.",
        "# Folder IDs are shown in the Syncthing Web UI under each folder's label.",
        "# Example:",
        "#   default",
        "#   photos-abc12"
    ) | Set-Content -Path $watchListPath -Encoding UTF8
    Write-Log "Created '$watchListPath'. Please add your Syncthing folder IDs and restart the script." "WARN"
    exit 0
}

$watchedFolders = @(Get-Content $watchListPath |
    Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' } |
    ForEach-Object { $_.Trim() })

if ($watchedFolders.Count -eq 0) {
    Write-Log "'$watchListPath' exists but contains no folder IDs. Add at least one and restart." "WARN"
    exit 0
}

# ── targetfolder.txt ─────────────────────────
$targetFolderPath = Join-Path $SCRIPT_DIR "targetfolder.txt"

if (-not (Test-Path $targetFolderPath)) {
    @(
        "# Target Directory",
        "# Write the full path of the destination folder on the line below this comment.",
        "# Example:  D:\Photos\Imported"
    ) | Set-Content -Path $targetFolderPath -Encoding UTF8
    Write-Log "Created '$targetFolderPath'. Please enter the target folder path and restart the script." "WARN"
    exit 0
}

$targetDir = (@(Get-Content $targetFolderPath |
    Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' } |
    Select-Object -First 1) | Select-Object -First 1).Trim().Trim('"').Trim("'")

if ([string]::IsNullOrWhiteSpace($targetDir)) {
    Write-Log "'$targetFolderPath' has no target directory. Add the path and restart." "WARN"
    exit 0
}

if (-not (Test-Path $targetDir)) {
    Write-Log "Target directory '$targetDir' does not exist. Creating it..." "WARN"
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# ── Stale manifest check ──────────────────────
# If a moved_files_*.txt exists on startup, the next-stage script was likely
# killed before it could delete its manifest.  Warn and block new batches until
# the operator resolves them to avoid silently overwriting the recovery record.
function Get-StaleManifests {
    return @(Get-ChildItem -Path $SCRIPT_DIR -Filter "moved_files_*.txt" -File -ErrorAction SilentlyContinue)
}

$staleManifests = @(Get-StaleManifests)
if ($staleManifests.Count -gt 0) {
    Write-Log "=== STALE MANIFEST(S) DETECTED ===" "WARN"
    foreach ($m in $staleManifests) {
        Write-Log "  $($m.FullName)" "WARN"
    }
    Write-Log "These were left by a previous run of Process-Files.ps1 that did not complete." "WARN"
    Write-Log "Review them manually, then delete them before new batches will be processed." "WARN"
    Write-Log "Script will keep running and watching, but will NOT move files until all stale manifests are gone." "WARN"
}

# ── Syncthing API helpers ─────────────────────
$apiHeaders = @{ "X-API-Key" = $ST_API_KEY }

function Get-FolderStatus {
    param([string]$FolderID)
    $uri = "$ST_BASE_URL/rest/db/status?folder=$([uri]::EscapeDataString($FolderID))"
    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $apiHeaders -Method Get -TimeoutSec 10
        return $resp
    }
    catch {
        Write-Log "API error querying folder '$FolderID': $_" "ERROR"
        return $null
    }
}

function Get-SyncthingFolderPath {
    param([string]$FolderID)
    $uri = "$ST_BASE_URL/rest/config/folders/$([uri]::EscapeDataString($FolderID))"
    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $apiHeaders -Method Get -TimeoutSec 10
        return $resp.path
    }
    catch {
        Write-Log "Could not retrieve path for folder '$FolderID': $_" "ERROR"
        return $null
    }
}

# ── Resolve local paths once ──────────────────
Write-Log "Resolving local paths for watched folders..."
$folderPaths = @{}   # FolderID → local path

foreach ($fid in $watchedFolders) {
    $path = Get-SyncthingFolderPath -FolderID $fid
    if ($path) {
        $folderPaths[$fid] = $path
        Write-Log "  '$fid' → $path"
    }
    else {
        Write-Log "  '$fid' → path not found; folder will still be watched for idle state."
    }
}

# ── Move top-level files ──────────────────────
# Returns a list of destination paths for every file successfully moved.
function Move-TopLevelFiles {
    param([string]$SourceDir, [string]$FolderID)

    $movedPaths = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path $SourceDir)) {
        Write-Log "Source path '$SourceDir' not found; skipping move." "WARN"
        return $movedPaths
    }

    $files = @(Get-ChildItem -Path $SourceDir -File)   # top-level files only

    if ($files.Count -eq 0) {
        Write-Log "No top-level files found in '$SourceDir' (folder: $FolderID)."
        return $movedPaths
    }

    Write-Log "Moving $($files.Count) file(s) from '$SourceDir' → '$targetDir'..."

    foreach ($file in $files) {
        $dest = Join-Path $targetDir $file.Name

        # Avoid overwriting: append a counter suffix if name already exists
        if (Test-Path $dest) {
            $base    = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $ext     = [System.IO.Path]::GetExtension($file.Name)
            $counter = 1
            do {
                $dest = Join-Path $targetDir "${base}_${counter}${ext}"
                $counter++
            } while (Test-Path $dest)
        }

        try {
            Move-Item -Path $file.FullName -Destination $dest -Force
            Write-Log "  Moved: $($file.Name) → $dest"
            $movedPaths.Add($dest)
        }
        catch {
            Write-Log "  Failed to move '$($file.Name)': $_" "ERROR"
        }
    }

    return $movedPaths
}

# ── Write manifest & invoke next script ───────
function Invoke-NextStage {
    param([string[]]$MovedFiles)

    if ($MovedFiles.Count -eq 0) {
        Write-Log "No files were moved; skipping next-stage invocation."
        return
    }

    # Timestamped manifest — unique per batch, never overwrites a prior one
    $ts           = Get-Date -Format "yyyyMMdd_HHmmss"
    $manifestPath = Join-Path $SCRIPT_DIR "moved_files_${ts}.txt"

    try {
        $MovedFiles | Set-Content -Path $manifestPath -Encoding UTF8
        Write-Log "Manifest written: $manifestPath ($($MovedFiles.Count) entries)"
    }
    catch {
        Write-Log "Failed to write manifest '$manifestPath': $_" "ERROR"
        return
    }

    if (-not (Test-Path $NEXT_SCRIPT)) {
        Write-Log "Next-stage script not found at '$NEXT_SCRIPT'; manifest left for manual processing." "WARN"
        return
    }

    Write-Log "Invoking next-stage script: $NEXT_SCRIPT"
    try {
        # Run synchronously so we know it finished before the next poll cycle
        Write-Debug "File received. Attempting to run the next script"
        & pwsh -NonInteractive -File $NEXT_SCRIPT -ManifestPath $manifestPath
        Write-Log "Next-stage script completed."
    }
    catch {
        Write-Log "Next-stage script threw an error: $_" "ERROR"
        Write-Log "Manifest '$manifestPath' was NOT deleted; review and reprocess manually." "WARN"
    }
}

# ── Main polling loop ─────────────────────────
Write-Log "=== Sync-AndMove started ==="
Write-Log "Watching folders : $($watchedFolders -join ', ')"
Write-Log "Target directory : $targetDir"
Write-Log "Next-stage script: $NEXT_SCRIPT"
Write-Log "Poll interval    : $POLL_SECONDS seconds"
Write-Log "Press Ctrl+C to stop."

# Track which folders we have already processed this idle cycle so we don't
# move files repeatedly while everything stays idle.
$processedIdle = @{}
foreach ($fid in $watchedFolders) { $processedIdle[$fid] = $false }

while ($true) {

    # ── Stale-manifest gate ───────────────────
    # Re-check every loop so the operator can drop the manifests and resume
    # without restarting the script.
    if (@(Get-StaleManifests).Count -gt 0) {
        Write-Log "Stale manifest(s) still present — skipping move/invoke until resolved." "WARN"
        Start-Sleep -Seconds $POLL_SECONDS
        continue
    }

    $allIdle = $true

    foreach ($fid in $watchedFolders) {
        $status = Get-FolderStatus -FolderID $fid

        if ($null -eq $status) {
            # API unreachable; treat as non-idle to be safe
            $allIdle = $false
            continue
        }

        $state = $status.state   # "idle" | "syncing" | "scanning" | "error" …

        if ($state -ne "idle") {
            $allIdle = $false
            $processedIdle[$fid] = $false   # reset so we process again after next sync
            Write-Log "Folder '$fid' is '$state'..."
        }
    }

    if ($allIdle) {
        $batchFiles = [System.Collections.Generic.List[string]]::new()

        foreach ($fid in $watchedFolders) {
            if (-not $processedIdle[$fid]) {
                $srcPath = $folderPaths[$fid]

                if ($srcPath) {
                    if ($ENABLE_MOVE) {
                        Write-Log "Folder '$fid' is idle — starting file move."
                        $moved = Move-TopLevelFiles -SourceDir $srcPath -FolderID $fid
                        foreach ($p in $moved) { $batchFiles.Add($p) }
                    }
                    else {
                        Write-Log "Folder '$fid' is idle — move disabled, collecting files in-place."
                        $inPlace = @(Get-ChildItem -Path $srcPath -File)
                        foreach ($f in $inPlace) { $batchFiles.Add($f.FullName) }
                    }
                }
                else {
                    Write-Log "No local path cached for '$fid'; skipping." "WARN"
                }

                $processedIdle[$fid] = $true
            }
        }

        # Invoke next stage with whichever paths were collected
        if ($batchFiles.Count -gt 0) {
            Invoke-NextStage -MovedFiles $batchFiles.ToArray()
        }
    }

    Start-Sleep -Seconds $POLL_SECONDS
}