param (
    [string]$Directory1,
    [string]$Directory2,

    [switch]$IdenticalTest,
    [switch]$SingleDirectory
)

# -------------------------------
# PARAMETER VALIDATION
# -------------------------------

if ($SingleDirectory) {
    if ($Directory2) {
        Write-Error "❌ -SingleDirectory cannot be used with -Directory2"
        exit 1
    }

    if (-not $Directory1) {
        Write-Error "❌ -SingleDirectory requires -Directory1"
        exit 1
    }
}
else {
    if (-not $Directory1 -or -not $Directory2) {
        Write-Error "❌ Both -Directory1 and -Directory2 are required (unless using -SingleDirectory)"
        exit 1
    }
}

# Validate directories
$dirsToCheck = @($Directory1)
if (-not $SingleDirectory) { $dirsToCheck += $Directory2 }

foreach ($dir in $dirsToCheck) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
        Write-Error "Directory does not exist: $dir"
        exit 1
    }
}

Write-Host "🔍 Scanning..." -ForegroundColor Cyan

# -------------------------------
# HASH FUNCTION
# -------------------------------
function Get-FileHashes {
    param ([string]$Path)

    $hashTable = @{}

    Get-ChildItem -Path $Path -File -Recurse | ForEach-Object {
        try {
            $sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
            $md5    = (Get-FileHash $_.FullName -Algorithm MD5).Hash
            $key = "$sha256|$md5"

            if (-not $hashTable.ContainsKey($key)) {
                $hashTable[$key] = @()
            }

            $hashTable[$key] += $_.FullName
        }
        catch {
            Write-Warning "Failed to hash: $($_.FullName)"
        }
    }

    return $hashTable
}

# -------------------------------
# SINGLE DIRECTORY MODE
# -------------------------------
if ($SingleDirectory) {

    Write-Host "📁 Single directory duplicate check..." -ForegroundColor Yellow

    $hashes = Get-FileHashes -Path $Directory1
    $results = @()

    foreach ($key in $hashes.Keys) {
        if ($hashes[$key].Count -gt 1) {
            $sha256, $md5 = $key -split '\|'

            $files = $hashes[$key]

            for ($i = 0; $i -lt $files.Count; $i++) {
                for ($j = $i + 1; $j -lt $files.Count; $j++) {
                    $results += [PSCustomObject]@{
                        File1  = $files[$i]
                        File2  = $files[$j]
                        SHA256 = $sha256
                        MD5    = $md5
                    }
                }
            }
        }
    }

    if ($results.Count -eq 0) {
        Write-Host "❌ No duplicates found." -ForegroundColor Red
    } else {
        Write-Host "✅ Duplicates found:" -ForegroundColor Green
        $results | Format-Table -AutoSize
    }

    exit
}

# Build hash dictionaries
$hashes1 = Get-FileHashes -Path $Directory1
$hashes2 = Get-FileHashes -Path $Directory2

# -------------------------------
# IDENTICAL TEST MODE
# -------------------------------

if ($IdenticalTest) {
    Write-Host "🧪 Running identical test..." -ForegroundColor Magenta

    # Total file counts
    $count1 = ($hashes1.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    $count2 = ($hashes2.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum

    if ($count1 -ne $count2) {
        Write-Host "❌ Not identical: Different file counts ($count1 vs $count2)" -ForegroundColor Red
        exit
    }

    # Compare hash keys AND counts per hash
    foreach ($key in $hashes1.Keys) {
        if (-not $hashes2.ContainsKey($key)) {
            Write-Host "❌ Not identical: Missing hash in Directory2" -ForegroundColor Red
            exit
        }

        if ($hashes1[$key].Count -ne $hashes2[$key].Count) {
            Write-Host "❌ Not identical: Different file count for hash $key" -ForegroundColor Red
            exit
        }
    }

    # Also check for extra hashes in Directory2
    foreach ($key in $hashes2.Keys) {
        if (-not $hashes1.ContainsKey($key)) {
            Write-Host "❌ Not identical: Extra hash in Directory2" -ForegroundColor Red
            exit
        }
    }

    Write-Host "✅ Directories are IDENTICAL (same files & counts)." -ForegroundColor Green
    exit
}

# -------------------------------
# NORMAL DUPLICATE MODE
# -------------------------------

Write-Host "🔗 Comparing hashes..." -ForegroundColor Yellow

$results = @()

foreach ($key in $hashes1.Keys) {
    if ($hashes2.ContainsKey($key)) {
        $sha256, $md5 = $key -split '\|'

        foreach ($file1 in $hashes1[$key]) {
            foreach ($file2 in $hashes2[$key]) {
                $results += [PSCustomObject]@{
                    Directory1 = $file1
                    Directory2 = $file2
                    SHA256     = $sha256
                    MD5        = $md5
                }
            }
        }
    }
}

# Output
if ($results.Count -eq 0) {
    Write-Host "`n❌ No duplicates found." -ForegroundColor Red
} else {
    Write-Host "`n✅ Duplicates found:" -ForegroundColor Green
    $results | Format-Table -AutoSize
}
