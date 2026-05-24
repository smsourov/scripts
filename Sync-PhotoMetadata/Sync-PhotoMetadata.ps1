#Requires -Version 7.0

<#
.SYNOPSIS
    Synchronizes photo filenames with EXIF datetime metadata and vice versa.

.DESCRIPTION
    Scans directories for JPG/HEIC photo files named in YYYYMMDD_HHMMSS or
    YYYYMMDD_HHMMSS_NNN format, then reports mismatches between filenames and
    embedded EXIF DateTimeOriginal metadata. Optionally renames files to match
    their EXIF data, updates EXIF data to match filenames, and copies or moves
    the processed files to a destination directory.

.PARAMETER Directory
    The directory containing photo files to process.
    Cannot be used together with -List.

.PARAMETER List
    Path to a plain-text file containing one directory path per line.
    Cannot be used together with -Directory.

.PARAMETER ModifyFilename
    Switch. When present, renames each eligible file to YYYYMMDD_HHMMSS.ext derived
    from its EXIF DateTimeOriginal. Combine with -WrongFilenameOnly to limit
    renaming to files whose name does not already match the EXIF datetime.

.PARAMETER ModifyExifDatetime
    Switch. When present, writes the datetime encoded in the filename into the file's
    EXIF DateTimeOriginal (and CreateDate / ModifyDate) tags. Combine with
    -MissingExifDatetimeOnly to limit updates to files that currently have no
    EXIF datetime at all.

.PARAMETER CopyToDirectory
    Destination directory for a copy of every processed file.
    Cannot be used together with -MoveToDirectory.

.PARAMETER MoveToDirectory
    Destination directory; processed files are moved there.
    Cannot be used together with -CopyToDirectory.

.PARAMETER MissingExifDatetimeOnly
    Restricts -ModifyExifDatetime to files that have no EXIF datetime tag.
    Requires -ModifyExifDatetime to also be specified.

.PARAMETER WrongFilenameOnly
    Restricts -ModifyFilename to files whose current name does not match
    their EXIF datetime (including files with an _NNN suffix).
    Requires -ModifyFilename to also be specified.

.PARAMETER ExifToolLocation
    Full path to the exiftool executable.

.PARAMETER Confirm
    When present, suppresses the interactive Y/N confirmation prompt that
    would otherwise appear before any -CopyToDirectory or -MoveToDirectory
    operation.

.EXAMPLE
    .\Sync-PhotoMetadata.ps1 `
        -Directory  "D:\Photos\2024" `
        -ExifToolLocation "C:\Tools\exiftool.exe" `
        -ModifyFilename

.EXAMPLE
    .\Sync-PhotoMetadata.ps1 `
        -Directory  "D:\Photos\2024" `
        -ExifToolLocation "C:\Tools\exiftool.exe" `
        -ModifyFilename `
        -WrongFilenameOnly `
        -MoveToDirectory "D:\Photos\Fixed" `
        -Confirm

.EXAMPLE
    .\Sync-PhotoMetadata.ps1 `
        -List "C:\photo-dirs.txt" `
        -ExifToolLocation "C:\Tools\exiftool.exe" `
        -ModifyExifDatetime `
        -MissingExifDatetimeOnly
#>

param(
    # ── Source ────────────────────────────────────────────────────────────────
    [Parameter(Mandatory = $false)]
    [string]$Directory,

    [Parameter(Mandatory = $false)]
    [string]$List,

    # ── Operations ────────────────────────────────────────────────────────────
    [Parameter(Mandatory = $false)]
    [switch]$ModifyFilename,

    [Parameter(Mandatory = $false)]
    [switch]$ModifyExifDatetime,

    # ── Destination ───────────────────────────────────────────────────────────
    [Parameter(Mandatory = $false)]
    [string]$CopyToDirectory,

    [Parameter(Mandatory = $false)]
    [string]$MoveToDirectory,

    # ── Filters ───────────────────────────────────────────────────────────────
    [Parameter(Mandatory = $false)]
    [switch]$MissingExifDatetimeOnly,

    [Parameter(Mandatory = $false)]
    [switch]$WrongFilenameOnly,

    # ── Tool ──────────────────────────────────────────────────────────────────
    [Parameter(Mandatory = $true)]
    [string]$ExifToolLocation,

    # ── Behaviour ─────────────────────────────────────────────────────────────
    [Parameter(Mandatory = $false)]
    [switch]$Confirm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ══════════════════════════════════════════════════════════════════════════════
#  HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Write-Banner {
    param([string]$Title)
    $bar = '═' * 72
    Write-Host ''
    Write-Host $bar                -ForegroundColor Cyan
    Write-Host "  $Title"          -ForegroundColor Cyan
    Write-Host $bar                -ForegroundColor Cyan
}

function Write-Step    { param([string]$m) Write-Host "  »  $m" }
function Write-Ok      { param([string]$m) Write-Host "  ✔  $m" -ForegroundColor Green  }
function Write-Warning { param([string]$m) Write-Host "  ⚠  $m" -ForegroundColor Yellow }
function Write-Failure { param([string]$m) Write-Host "  ✖  $m" -ForegroundColor Red    }

function Stop-WithError {
    param([string]$Message)
    Write-Failure $Message
    exit 1
}

# ── DateTime helpers ──────────────────────────────────────────────────────────

# Parses EXIF datetime string "YYYY:MM:DD HH:MM:SS[+offset]" → [datetime] or $null
function ConvertFrom-ExifDateString {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    # Strip optional timezone component
    $clean = ($Raw -split '[+\-Z]')[0].Trim()
    try {
        return [datetime]::ParseExact($clean, 'yyyy:MM:dd HH:mm:ss', $null)
    } catch {
        return $null
    }
}

# Parses a file base-name "YYYYMMDD_HHMMSS[_NNN]" → [datetime] or $null
function ConvertFrom-FilenameDateTime {
    param([string]$BaseName)
    if ($BaseName -match '^(\d{8}_\d{6})(?:_\d+)?$') {
        try {
            return [datetime]::ParseExact($Matches[1], 'yyyyMMdd_HHmmss', $null)
        } catch {
            return $null
        }
    }
    return $null
}

# [datetime] → "yyyy:MM:dd HH:mm:ss"  (exiftool write format)
function ConvertTo-ExifDateString {
    param([datetime]$dt)
    return $dt.ToString('yyyy:MM:dd HH:mm:ss')
}

# [datetime] → "yyyyMMdd_HHmmss"  (target filename stem)
function ConvertTo-FilenameStem {
    param([datetime]$dt)
    return $dt.ToString('yyyyMMdd_HHmmss')
}

# ── ExifTool wrapper ──────────────────────────────────────────────────────────

function Get-ExifDateTimeOriginal {
    param([string]$FilePath)
    try {
        # -s3  → value only, no tag name, no padding
        $raw = & $ExifToolLocation -DateTimeOriginal -s3 $FilePath 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ConvertFrom-ExifDateString ($raw | Select-Object -First 1).Trim()
    } catch {
        return $null
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  PARAMETER VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

Write-Banner 'Sync-PhotoMetadata  —  Parameter Validation'

# Strip any stray surrounding quotes a user might type at an interactive prompt
foreach ($varName in @("Directory","List","CopyToDirectory","MoveToDirectory","ExifToolLocation")) {
    if ($PSBoundParameters.ContainsKey($varName)) {
        $val = Get-Variable -Name $varName -ValueOnly
        $trimmed = $val.Trim().Trim('"').Trim()
        Set-Variable -Name $varName -Value $trimmed
    }
}

$hasDirectory  = $PSBoundParameters.ContainsKey('Directory')
$hasList       = $PSBoundParameters.ContainsKey('List')
$hasCopyTo     = $PSBoundParameters.ContainsKey('CopyToDirectory')
$hasMoveT      = $PSBoundParameters.ContainsKey('MoveToDirectory')

# ── Source ────────────────────────────────────────────────────────────────────

if ($hasDirectory -and $hasList) {
    Stop-WithError '-Directory and -List cannot be used together.'
}
if (-not $hasDirectory -and -not $hasList) {
    Stop-WithError 'You must supply either -Directory or -List.'
}
if ($hasDirectory -and [string]::IsNullOrWhiteSpace($Directory)) {
    Stop-WithError '-Directory cannot be empty.'
}
if ($hasList -and [string]::IsNullOrWhiteSpace($List)) {
    Stop-WithError '-List cannot be empty.'
}

# ── Destination ───────────────────────────────────────────────────────────────

if ($hasCopyTo -and $hasMoveT) {
    Stop-WithError '-CopyToDirectory and -MoveToDirectory cannot be used together.'
}
if ($hasCopyTo -and [string]::IsNullOrWhiteSpace($CopyToDirectory)) {
    Stop-WithError '-CopyToDirectory cannot be empty.'
}
if ($hasMoveT -and [string]::IsNullOrWhiteSpace($MoveToDirectory)) {
    Stop-WithError '-MoveToDirectory cannot be empty.'
}

# ── Filter guards ─────────────────────────────────────────────────────────────

if ($MissingExifDatetimeOnly -and -not $ModifyExifDatetime) {
    Stop-WithError '-MissingExifDatetimeOnly requires -ModifyExifDatetime.'
}
if ($WrongFilenameOnly -and -not $ModifyFilename) {
    Stop-WithError '-WrongFilenameOnly requires -ModifyFilename.'
}

# ── ExifTool ──────────────────────────────────────────────────────────────────

if ([string]::IsNullOrWhiteSpace($ExifToolLocation)) {
    Stop-WithError '-ExifToolLocation cannot be empty.'
}
if (-not (Test-Path -LiteralPath $ExifToolLocation -PathType Leaf)) {
    Stop-WithError "ExifTool binary not found at: $ExifToolLocation"
}

try {
    $etVer = (& $ExifToolLocation -ver 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'non-zero exit' }
    Write-Ok "ExifTool v$etVer detected."
} catch {
    Stop-WithError "ExifTool at '$ExifToolLocation' did not respond correctly."
}

Write-Ok 'All parameters are valid.'

# ══════════════════════════════════════════════════════════════════════════════
#  COLLECT DIRECTORIES
# ══════════════════════════════════════════════════════════════════════════════

Write-Banner 'Collecting Directories'

$targetDirs = [System.Collections.Generic.List[string]]::new()

if ($hasDirectory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        Stop-WithError "Directory not found: $Directory"
    }
    $targetDirs.Add($Directory)
    Write-Ok "Source directory: $Directory"
} else {
    if (-not (Test-Path -LiteralPath $List -PathType Leaf)) {
        Stop-WithError "List file not found: $List"
    }

    $lines = Get-Content -LiteralPath $List |
             Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
             ForEach-Object { $_.Trim() }

    foreach ($line in $lines) {
        if (-not (Test-Path -LiteralPath $line -PathType Container)) {
            Write-Warning "Skipping — directory not found: $line"
        } else {
            $targetDirs.Add($line)
        }
    }

    if ($targetDirs.Count -eq 0) {
        Stop-WithError "No valid directories found in: $List"
    }

    Write-Ok "$($targetDirs.Count) valid director(ies) loaded from list."
}

# ══════════════════════════════════════════════════════════════════════════════
#  COLLECT FILES
# ══════════════════════════════════════════════════════════════════════════════

Write-Banner 'Collecting Files'

$allFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

foreach ($dir in $targetDirs) {
    $found = Get-ChildItem -LiteralPath $dir -File |
             Where-Object { $_.Extension -imatch '^\.(jpg|jpeg|heic)$' }
    $count = @($found).Count
    Write-Step "$count file(s) in: $dir"
    foreach ($f in $found) { $allFiles.Add($f) }
}

if ($allFiles.Count -eq 0) {
    Write-Warning 'No JPG or HEIC files found. Nothing to do.'
    exit 0
}

Write-Ok "Total: $($allFiles.Count) file(s) queued for analysis."

# ══════════════════════════════════════════════════════════════════════════════
#  ANALYSE FILES
# ══════════════════════════════════════════════════════════════════════════════

Write-Banner 'Analysing Files'

$records = [System.Collections.Generic.List[PSCustomObject]]::new()
$idx     = 0

foreach ($file in $allFiles) {
    $idx++
    $pct = [int](($idx / $allFiles.Count) * 100)
    Write-Progress -Activity 'Reading EXIF metadata' `
                   -Status   "$idx / $($allFiles.Count) — $($file.Name)" `
                   -PercentComplete $pct

    $baseName = $file.BaseName
    $ext      = $file.Extension.ToLower()    # .jpg / .heic (normalised)

    $fnDt     = ConvertFrom-FilenameDateTime $baseName   # [datetime] or $null
    $exifDt   = Get-ExifDateTimeOriginal $file.FullName  # [datetime] or $null

    # Structural flags
    $hasValidFormat    = ($baseName -match '^\d{8}_\d{6}(?:_\d+)?$')
    $hasExtraSuffix    = ($baseName -match '^\d{8}_\d{6}_\d+$')
    $isMissingExif     = ($null -eq $exifDt)

    # Correctness: filename stem matches EXIF and has no _NNN suffix
    $isCorrect = (
        $null -ne $fnDt -and
        $null -ne $exifDt -and
        $fnDt -eq $exifDt -and
        -not $hasExtraSuffix
    )

    # "Wrong filename" = parseable file, but stem ≠ EXIF (or has _NNN suffix
    # even when times would otherwise match), or name is entirely unparseable
    $isWrongFilename = -not $isCorrect -and -not $isMissingExif

    $record = [PSCustomObject]@{
        File               = $file
        FullPath           = $file.FullName
        CurrentName        = $file.Name
        BaseName           = $baseName
        Extension          = $ext
        FilenameDateTime   = $fnDt
        ExifDateTime       = $exifDt
        HasValidFormat     = $hasValidFormat
        HasExtraSuffix     = $hasExtraSuffix
        IsMissingExif      = $isMissingExif
        IsCorrect          = $isCorrect
        IsWrongFilename    = $isWrongFilename
        # Tracks the live path; updated when the file is renamed later
        LivePath           = $file.FullName
    }

    $records.Add($record)
}

Write-Progress -Activity 'Reading EXIF metadata' -Completed

# ══════════════════════════════════════════════════════════════════════════════
#  ANALYSIS REPORT
# ══════════════════════════════════════════════════════════════════════════════

Write-Banner 'Analysis Report'

$total           = $records.Count
$correctCount    = @($records | Where-Object { $_.IsCorrect           }).Count
$wrongNameCount  = @($records | Where-Object { $_.IsWrongFilename     }).Count
$extraSufCount   = @($records | Where-Object { $_.HasExtraSuffix      }).Count
$missingExifCnt  = @($records | Where-Object { $_.IsMissingExif       }).Count
$unparseableCnt  = @($records | Where-Object { -not $_.HasValidFormat }).Count

Write-Host ''
Write-Host ('  {0,-28}  {1}' -f 'Total files analysed',   $total)          -ForegroundColor White
Write-Host ('  {0,-28}  {1}' -f 'Correct  (name = EXIF)', $correctCount)   -ForegroundColor Green
Write-Host ('  {0,-28}  {1}' -f 'Wrong filename',          $wrongNameCount) -ForegroundColor Yellow
Write-Host ('  {0,-28}  {1}' -f '  └─ Extra _NNN suffix',  $extraSufCount)  -ForegroundColor DarkYellow
Write-Host ('  {0,-28}  {1}' -f '  └─ Unparseable name',   $unparseableCnt) -ForegroundColor DarkYellow
Write-Host ('  {0,-28}  {1}' -f 'Missing EXIF datetime',   $missingExifCnt) -ForegroundColor Red

# ── Mismatch table ────────────────────────────────────────────────────────────

$problemRecords = @($records |
    Where-Object { $_.IsWrongFilename -or $_.IsMissingExif })

if ($problemRecords.Count -gt 0) {
    Write-Host ''
    Write-Host "  Files with mismatched or missing datetime ($($problemRecords.Count)):" `
               -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('  {0,-46}  {1,-21}  {2,-21}  {3}' -f
        'Filename', 'Filename datetime', 'EXIF datetime', 'Issue') `
        -ForegroundColor Cyan
    Write-Host ('  {0}  {1}  {2}  {3}' -f
        ('-' * 46), ('-' * 21), ('-' * 21), ('-' * 18)) `
        -ForegroundColor DarkGray

    foreach ($r in $problemRecords) {
        $nameDisplay = $r.CurrentName
        if ($nameDisplay.Length -gt 45) { $nameDisplay = $nameDisplay.Substring(0, 42) + '...' }

        $fnStr   = if ($r.FilenameDateTime) {
                       $r.FilenameDateTime.ToString('yyyy-MM-dd HH:mm:ss')
                   } else { '(unparseable)' }

        $exifStr = if ($r.ExifDateTime) {
                       $r.ExifDateTime.ToString('yyyy-MM-dd HH:mm:ss')
                   } else { '(missing)' }

        $issue   = switch ($true) {
            $r.IsMissingExif   { 'No EXIF datetime';    break }
            $r.HasExtraSuffix  { '_NNN suffix present'; break }
            default            { 'Name ≠ EXIF'                }
        }

        $color = if ($r.IsMissingExif) { 'Red' } else { 'Yellow' }
        Write-Host ('  {0,-46}  {1,-21}  {2,-21}  {3}' -f
            $nameDisplay, $fnStr, $exifStr, $issue) -ForegroundColor $color
    }
} else {
    Write-Host ''
    Write-Ok 'All files have consistent filenames and EXIF datetimes.'
}

# ══════════════════════════════════════════════════════════════════════════════
#  MODIFY FILENAMES  (EXIF → filename)
# ══════════════════════════════════════════════════════════════════════════════

if ($ModifyFilename) {
    Write-Banner 'Modifying Filenames  (EXIF → Filename)'

    # Which records are eligible?
    if ($WrongFilenameOnly) {
        # Only files that are wrong AND have EXIF to read from
        $eligible = @($records | Where-Object { $_.IsWrongFilename -and -not $_.IsMissingExif })
        Write-Step "Scope: wrong-filename files with EXIF data ($($eligible.Count) file(s))."
    } else {
        # All files that have EXIF (we can still no-op if name is already correct)
        $eligible = @($records | Where-Object { -not $_.IsMissingExif })
        Write-Step "Scope: all files with EXIF data ($($eligible.Count) file(s))."
    }

    if ($eligible.Count -eq 0) {
        Write-Warning 'No eligible files for filename modification.'
    } else {
        # ── Confirmation ──────────────────────────────────────────────────────
        if (-not $Confirm) {
            Write-Host ''
            Write-Host "  You are about to rename $($eligible.Count) file(s) in-place based on their EXIF datetime." `
                       -ForegroundColor Yellow
            Write-Host '  This operation modifies the original files directly.' `
                       -ForegroundColor Yellow
            Write-Host ''
            $answer = Read-Host '  Proceed? [Y / N]'
            if ($answer -notmatch '^[Yy]$') {
                Write-Warning 'Rename operation cancelled by user. No files were renamed.'
                # Skip to next section rather than exit, in case other operations follow
                $eligible = @()
            }
        }
    }

    if ($eligible.Count -eq 0 -and $ModifyFilename) {
        # Already printed a warning above; nothing more to do in this block.
    } elseif ($eligible.Count -gt 0) {
        $renamed  = 0
        $skipped  = 0
        $failed   = 0

        foreach ($r in $eligible) {
            $dir          = Split-Path $r.LivePath -Parent
            $targetStem   = ConvertTo-FilenameStem $r.ExifDateTime
            $targetName   = "$targetStem$($r.Extension)"
            $targetPath   = Join-Path $dir $targetName

            # Already correct — skip silently (counts as skipped)
            if ([System.IO.Path]::GetFullPath($targetPath) -eq [System.IO.Path]::GetFullPath($r.LivePath)) {
                $skipped++
                continue
            }

            # Collision resolution: append _1, _2, … until free
            if (Test-Path -LiteralPath $targetPath) {
                $suffix = 1
                do {
                    $targetName = "${targetStem}_${suffix}$($r.Extension)"
                    $targetPath = Join-Path $dir $targetName
                    $suffix++
                } while (Test-Path -LiteralPath $targetPath)
                Write-Warning "Collision resolved for '$($r.CurrentName)' → using '$targetName'"
            }

            try {
                Rename-Item -LiteralPath $r.LivePath -NewName $targetName -ErrorAction Stop
                Write-Ok "Renamed: '$($r.CurrentName)' → '$targetName'"
                # Track the new live path for subsequent copy/move
                $r.LivePath    = $targetPath
                $r.CurrentName = $targetName
                $renamed++
            } catch {
                Write-Failure "Failed to rename '$($r.CurrentName)': $_"
                $failed++
            }
        }

        Write-Host ''
        Write-Host "  Rename summary ─── Renamed: $renamed   Already correct: $skipped   Failed: $failed"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  MODIFY EXIF DATETIME  (filename → EXIF)
# ══════════════════════════════════════════════════════════════════════════════

if ($ModifyExifDatetime) {
    Write-Banner 'Modifying EXIF Datetime  (Filename → EXIF)'

    if ($MissingExifDatetimeOnly) {
        $eligible = @($records |
            Where-Object { $_.IsMissingExif -and $null -ne $_.FilenameDateTime })
        Write-Step "Scope: files missing EXIF datetime with parseable filename ($($eligible.Count) file(s))."
    } else {
        $eligible = @($records | Where-Object { $null -ne $_.FilenameDateTime })
        Write-Step "Scope: all files with parseable filename ($($eligible.Count) file(s))."
    }

    if ($eligible.Count -eq 0) {
        Write-Warning 'No eligible files for EXIF datetime modification.'
    } else {
        # ── Confirmation ──────────────────────────────────────────────────────
        if (-not $Confirm) {
            Write-Host ''
            Write-Host "  You are about to overwrite EXIF datetime tags in $($eligible.Count) file(s) based on their filename." `
                       -ForegroundColor Yellow
            Write-Host '  This operation modifies the original files directly.' `
                       -ForegroundColor Yellow
            Write-Host ''
            $answer = Read-Host '  Proceed? [Y / N]'
            if ($answer -notmatch '^[Yy]$') {
                Write-Warning 'EXIF update cancelled by user. No EXIF data was modified.'
                $eligible = @()
            }
        }
    }

    if ($eligible.Count -eq 0 -and $ModifyExifDatetime) {
        # Already printed a warning above; nothing more to do in this block.
    } elseif ($eligible.Count -gt 0) {
        $updated = 0
        $failed  = 0

        foreach ($r in $eligible) {
            $exifStr = ConvertTo-ExifDateString $r.FilenameDateTime

            try {
                # Write DateTimeOriginal, CreateDate, and ModifyDate
                $out = & $ExifToolLocation `
                    "-DateTimeOriginal=$exifStr" `
                    "-CreateDate=$exifStr" `
                    "-ModifyDate=$exifStr" `
                    -overwrite_original `
                    $r.LivePath 2>&1

                if ($LASTEXITCODE -ne 0) {
                    Write-Failure "ExifTool error on '$($r.CurrentName)': $out"
                    $failed++
                } else {
                    Write-Ok "EXIF updated: '$($r.CurrentName)' → $exifStr"
                    $updated++
                }
            } catch {
                Write-Failure "Exception updating EXIF for '$($r.CurrentName)': $_"
                $failed++
            }
        }

        Write-Host ''
        Write-Host "  EXIF update summary ─── Updated: $updated   Failed: $failed"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  COPY / MOVE FILES
# ══════════════════════════════════════════════════════════════════════════════

if ($hasCopyTo -or $hasMoveT) {
    $destDir   = if ($hasCopyTo) { $CopyToDirectory } else { $MoveToDirectory }
    $verb      = if ($hasCopyTo) { 'Copy'           } else { 'Move'           }
    $verbPast  = if ($hasCopyTo) { 'Copied'         } else { 'Moved'          }

    Write-Banner "$verb Files → Destination"
    Write-Step "Destination: $destDir"

    $destExists = Test-Path -LiteralPath $destDir -PathType Container
    if (-not $destExists) {
        Write-Warning 'Destination directory does not exist and will be created.'
    }

    # User confirmation
    if (-not $Confirm) {
        Write-Host ''
        Write-Host "  You are about to $($verb.ToLower()) $($records.Count) file(s) to:" `
                   -ForegroundColor Yellow
        Write-Host "    $destDir" -ForegroundColor Yellow
        Write-Host ''
        $answer = Read-Host '  Proceed? [Y / N]'
        if ($answer -notmatch '^[Yy]$') {
            Write-Warning 'Operation cancelled by user. No files were transferred.'
            exit 0
        }
    }

    # Ensure destination exists
    if (-not $destExists) {
        try {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Write-Ok "Created destination directory: $destDir"
        } catch {
            Stop-WithError "Could not create destination directory: $_"
        }
    }

    $succeeded = 0
    $failed    = 0

    foreach ($r in $records) {
        if (-not (Test-Path -LiteralPath $r.LivePath)) {
            Write-Warning "Source file no longer exists, skipping: $($r.LivePath)"
            $failed++
            continue
        }

        $leafName = Split-Path $r.LivePath -Leaf
        $destPath = Join-Path $destDir $leafName

        # Collision resolution at destination
        if (Test-Path -LiteralPath $destPath) {
            $stem    = [System.IO.Path]::GetFileNameWithoutExtension($leafName)
            $ext     = [System.IO.Path]::GetExtension($leafName)
            $suffix  = 1
            do {
                $leafName = "${stem}_${suffix}${ext}"
                $destPath = Join-Path $destDir $leafName
                $suffix++
            } while (Test-Path -LiteralPath $destPath)
            Write-Warning "Destination collision resolved → '$leafName'"
        }

        try {
            if ($hasCopyTo) {
                Copy-Item -LiteralPath $r.LivePath -Destination $destPath -ErrorAction Stop
            } else {
                Move-Item -LiteralPath $r.LivePath -Destination $destPath -ErrorAction Stop
                $r.LivePath    = $destPath
                $r.CurrentName = $leafName
            }
            Write-Ok "${verbPast}: '$leafName'"
            $succeeded++
        } catch {
            Write-Failure "Failed to $($verb.ToLower()) '$leafName': $_"
            $failed++
        }
    }

    Write-Host ''
    Write-Host "  Transfer summary ─── ${verbPast}: $succeeded   Failed: $failed"
}

# ══════════════════════════════════════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════════════════════════════════════

Write-Banner 'Finished'
Write-Ok 'Sync-PhotoMetadata completed.'
Write-Host ''