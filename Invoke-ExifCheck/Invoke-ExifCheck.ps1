#Requires -Version 7.0

param(
    [string]$Directory,
    [string]$Lists,

    [switch]$CheckExifPresenceOnly,
    [switch]$CheckExifDatePresenceOnly,

    [switch]$CheckExifAbsenceOnly,
    [switch]$CheckExifDateAbsenceOnly,

    [string]$MoveToDirectory,
    [string]$CopyToDirectory,

    [switch]$AllCores,
    [switch]$AllLogicalProcessors,

    [int]$MultiThread = 1,
    [string]$MagickLocation = "E:\Softwares\ImageMagick\ImageMagick-7.1.2-21-portable-Q16-HDRI-x64\magick.exe",

    [switch]$Confirm,
    [switch]$Force,

    [switch]$Help
)

function Show-WindowsTerminalProgress {
    param (
        [Parameter()]
        [int]$progress
    )
    Write-Host -NoNewline ("`e]9;4;1;$progress`a")
}

function Hide-WindowsTerminalProgress {
    Write-Host -NoNewline ("`e]9;4;0;0`a")
}


function Hide-Cursor {
    Write-Host "`e[?25l" -NoNewline
}

function Show-Cursor {
    Write-Host "`e[?25h" -NoNewline
}


# =========================
# SAFEMODE
# =========================

[bool]$safemode = $true

# =========================
# HELP
# =========================

if ($Help) {
    $helpFile = Join-Path $PSScriptRoot "README.md"

    if (Test-Path $helpFile) {
        Get-Content $helpFile
    }
    else {
        Write-Error "README.md not found."
    }

    exit
}

# =========================
# PARAMETER VALIDATION
# =========================

if ($Directory -and $Lists) {
    Write-Error "-Directory and -Lists cannot be used together."
    exit
}

if (-not $Directory -and -not $Lists) {
    Write-Error "Either -Directory or -Lists must be provided."
    exit
}

if ($MoveToDirectory -and $CopyToDirectory) {
    Write-Error "-MoveToDirectory and -CopyToDirectory cannot be used together."
    exit
}

if ($CheckExifPresenceOnly -and $CheckExifDatePresenceOnly) {
    Write-Error "-CheckExifPresenceOnly and -CheckExifDatePresenceOnly cannot be used together."
    exit
}

if ($CheckExifAbsenceOnly -and $CheckExifDateAbsenceOnly) {
    Write-Error "-CheckExifAbsenceOnly and -CheckExifDateAbsenceOnly cannot be used together."
    exit
}

if ($AllCores -and $AllLogicalProcessors) {
    Write-Error "-AllCores and -AllLogicalProcessors cannot be used together."
    exit
}

if ($AllCores -and $MultiThread -gt 1) {
    Write-Error "-AllCores and -MultiThread cannot be used together."
    exit
}

if ($AllLogicalProcessors -and $MultiThread -gt 1) {
    Write-Error "-AllLogicalProcessors and -MultiThread cannot be used together."
    exit
}

if ($safemode -and $Force) {
    Write-Error "-Force parameter is disabled."
    exit
}

# =========================
# DEFAULTS
# =========================

if (
    -not $CheckExifPresenceOnly `
        -and -not $CheckExifDatePresenceOnly `
        -and -not $CheckExifAbsenceOnly `
        -and -not $CheckExifDateAbsenceOnly
) {
    $CheckExifPresenceOnly = $true
}

# =========================================================
# CPU INFO
# =========================================================

$cpu = Get-CimInstance Win32_Processor

$totalCores = ($cpu | Measure-Object NumberOfCores -Sum).Sum
$totalLogical = ($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum

# =========================================================
# THREAD COUNT
# =========================================================

[int]$ThreadCount = 1

if ($AllCores) {
    $ThreadCount = $totalCores
}
elseif ($AllLogicalProcessors) {
    $ThreadCount = $totalLogical
}
elseif ($MultiThread -gt 1) {
    $ThreadCount = $MultiThread
}

Write-Host -ForegroundColor Blue "===== CPU and Threads ====="
Write-Host -ForegroundColor Green "CPU Cores: $($totalCores)"
Write-Host -ForegroundColor Green "Logical Processors: $($totalLogical)"
Write-Host -ForegroundColor Yellow "Treads Count: $($ThreadCount)"


# =========================
# DIRECTORY COLLECTION
# =========================

$directories = @()

if ($Directory) {
    if (-not (Test-Path $Directory)) {
        Write-Error "Directory does not exist: $Directory"
        exit
    }

    $directories += (Resolve-Path $Directory).Path
}

if ($Lists) {
    if (-not (Test-Path $Lists)) {
        Write-Error "List file does not exist: $Lists"
        exit
    }

    $directories += Get-Content $Lists
}

# =========================
# FILE COLLECTION
# =========================

$imageExtensions = @(
    "*.jpg",
    "*.jpeg",
    "*.png",
    "*.heic",
    "*.webp"
)

$allFiles = @()

foreach ($dir in $directories) {

    if (-not (Test-Path $dir)) {
        Write-Warning "Skipping invalid directory: $dir"
        continue
    }

    foreach ($ext in $imageExtensions) {
        $allFiles += Get-ChildItem -Path $dir -Filter $ext -File
    }
}

# =========================
# RESULT ARRAYS
# =========================

$ExifPresentFiles = @()
$ExifDatePresentFiles = @()

$ExifAbsentFiles = @()
$ExifDateAbsentFiles = @()

# =========================
# EXIF CHECKING
# =========================

# Get total number of files
$total = $allFiles.Length
# Store the starting time
$startTime = Get-Date
Write-Host -ForegroundColor Blue "Start time: $($startTime)"
<# 
ConcurrentDictionary variable for all ForEach-Object runspace where one update mean
update in every runspace
#>
$sharedDict = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()
# A `count` element acting as counter in the runspace 
$sharedDict['count'] = 0

$consoleWidth = $Host.UI.RawUI.WindowSize.Width
if ($consoleWidth -lt 10) { $consoleWidth = 80 } # fallback default


$consoleLock = [System.Object]::new()

Hide-Cursor

$processedFiles = $allFiles | ForEach-Object -ThrottleLimit $ThreadCount -Parallel {
    $width = $Using:consoleWidth

    # Location of the ImageMagick (magick) executable
    # The location has to be declared
    $magick = $Using:MagickLocation

    $lock = $Using:consoleLock
    # A local reference to be used and modified in the shared runtime of the ConcurrentDictionary
    $sharedDict = $Using:sharedDict
    # a local reference of the total quantity in the runtime
    $total = $Using:total
    # A local reference for each file and avoid the script from breaking
    $file = $_
    # update the counter
    $done = $sharedDict.AddOrUpdate(
        'count',
        1,
        [System.Func[string, int, int]] { param($k, $v) $v + 1 }
    )

    function Show-WindowsTerminalProgress {
        param (
            [Parameter()]
            [int]$progress
        )
        Write-Host -NoNewline ("`e]9;4;1;$progress`a")
    }

    function Get-Percentage {
        param (
            [Parameter()]
            [float]
            $value,
            # Parameter help description
            [Parameter()]
            [float]
            $total
        )
        return ($value / $total) * 100
    }

    try {

        [int]$processingMethod = 2

        if ($processingMethod -eq 1) {

            # ANY EXIF
            $allExif = & $magick identify -format "%[EXIF:*]" "$($file.FullName)" 2>$null

            # DateTime EXIF
            $dateExif = & $magick identify -format "%[EXIF:DateTime]" "$($file.FullName)" 2>$null

            $hasExif = -not [string]::IsNullOrWhiteSpace($allExif)
            $hasDate = -not [string]::IsNullOrWhiteSpace($dateExif)
        
        }
        elseif ($processingMethod -eq 2) {
            <# Action when this condition is true #>

            $allExif = & $magick identify -format "%[EXIF:*]" "$($file.FullName)" 2>$null

            $hasExif = -not [string]::IsNullOrWhiteSpace($allExif)

            $hasDate = (
                $allExif -match 'DateTimeOriginal' -or
                $allExif -match 'DateTime'
            )
        }
        [PSCustomObject]@{
            File    = $file
            HasExif = $hasExif
            HasDate = $hasDate
            Success = $true
            Failed  = $false
        }
    }
    catch {
        Write-Warning "Failed: $($file.FullName)"
        [PSCustomObject]@{
            File    = $file
            HasExif = $false
            HasDate = $false
            Success = $false
            Failed  = $true
        }
    }
    finally {
        [int]$percentage = Get-Percentage -value $done -total $total
        Show-WindowsTerminalProgress -progress $percentage

        [System.Threading.Monitor]::Enter($lock)
        try {
            Write-Host "Progress: $($done)/$($total) ($($percentage)%)" -NoNewline
            $width = $Host.UI.RawUI.BufferSize.Width
            Write-Host (" " * $width + "`r") -NoNewline
        }
        finally {
            [System.Threading.Monitor]::Exit($lock)
        }
    }
}

Show-Cursor
Hide-WindowsTerminalProgress
$endTime = Get-Date
Write-Host -ForegroundColor Blue "End time: $($endTime)"
$elapsed = $endTime - $startTime


# =========================
# Process the results
# =========================

foreach ($f in $processedFiles) {
    if ($f.HasExif -eq $true) {
        $ExifPresentFiles += $f.File
    }
    if ($f.HasDate -eq $true) {
        $ExifDatePresentFiles += $f.File
    }
    if ($f.HasExif -eq $false) {
        $ExifAbsentFiles += $f.File
    }
    if ($f.HasDate -eq $false) {
        $ExifDateAbsentFiles += $f.File
    }
}

# =========================
# OUTPUT
# =========================

function Show-Results {
    param(
        [string]$Title,
        [array]$Files
    )

    Write-Host ""
    Write-Host "===== $Title ====="

    foreach ($f in $Files) {
        Write-Host $f.FullName
    }

    Write-Host "Total: $($Files.Count)"
}


if ($CheckExifPresenceOnly) {
    Show-Results "EXIF PRESENT" $ExifPresentFiles
}

if ($CheckExifDatePresenceOnly) {
    Show-Results "EXIF DATETIME PRESENT" $ExifDatePresentFiles
}

if ($CheckExifAbsenceOnly) {
    Show-Results "EXIF ABSENT" $ExifAbsentFiles
}

if ($CheckExifDateAbsenceOnly) {
    Show-Results "EXIF DATETIME ABSENT" $ExifDateAbsentFiles
}

Write-Host -ForegroundColor Green "Files in directory: $($allFiles.Length)"
Write-Host -ForegroundColor Green "Time taken $($elapsed)"

# =========================
# FILE OPERATION FUNCTION
# =========================

function Invoke-FileOperation {

    param(
        [array]$Files,
        [string]$TargetDirectory,
        [string]$SubDirectoryName,
        [string]$Operation
    )

    if (-not $Files -or $Files.Count -eq 0) {
        return
    }

    $finalDirectory = Join-Path $TargetDirectory $SubDirectoryName

    if (-not $Confirm) {

        $response = Read-Host "$Operation $($Files.Count) files to '$finalDirectory'? (Y/N)"

        if ($response -notin @("Y", "y")) {
            Write-Host "Skipped."
            return
        }
    }

    if (-not (Test-Path $finalDirectory)) {
        New-Item -ItemType Directory -Path $finalDirectory | Out-Null
    }

    foreach ($f in $Files) {

        $destination = Join-Path $finalDirectory $f.Name

        try {

            if ($Operation -eq "MOVE") {

                Move-Item `
                    -Path $f.FullName `
                    -Destination $destination `
                    -Force:$Force

            }
            elseif ($Operation -eq "COPY") {

                Copy-Item `
                    -Path $f.FullName `
                    -Destination $destination `
                    -Force:$Force
            }

        }
        catch {
            Write-Warning "Failed: $($f.FullName)"
        }
    }
}

# =========================
# MOVE / COPY
# =========================

if ($MoveToDirectory) {

    if ($CheckExifPresenceOnly) {
        Invoke-FileOperation $ExifPresentFiles $MoveToDirectory "ExifPresent" "MOVE"
    }

    if ($CheckExifDatePresenceOnly) {
        Invoke-FileOperation $ExifDatePresentFiles $MoveToDirectory "ExifDatePresent" "MOVE"
    }

    if ($CheckExifAbsenceOnly) {
        Invoke-FileOperation $ExifAbsentFiles $MoveToDirectory "ExifAbsent" "MOVE"
    }

    if ($CheckExifDateAbsenceOnly) {
        Invoke-FileOperation $ExifDateAbsentFiles $MoveToDirectory "ExifDateAbsent" "MOVE"
    }
}

if ($CopyToDirectory) {

    if ($CheckExifPresenceOnly) {
        Invoke-FileOperation $ExifPresentFiles $CopyToDirectory "ExifPresent" "COPY"
    }

    if ($CheckExifDatePresenceOnly) {
        Invoke-FileOperation $ExifDatePresentFiles $CopyToDirectory "ExifDatePresent" "COPY"
    }

    if ($CheckExifAbsenceOnly) {
        Invoke-FileOperation $ExifAbsentFiles $CopyToDirectory "ExifAbsent" "COPY"
    }

    if ($CheckExifDateAbsenceOnly) {
        Invoke-FileOperation $ExifDateAbsentFiles $CopyToDirectory "ExifDateAbsent" "COPY"
    }
}