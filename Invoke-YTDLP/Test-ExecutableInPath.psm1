function Test-ExecutableInPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    # ── Resolve candidate filenames based on OS ──────────────────────────────
    $candidates = @()

    if ($IsWindows -or (-not $IsLinux -and -not $IsMacOS)) {
        # Windows: ensure .exe / .com variants are always checked
        $base = $Name -replace '\.(exe|com)$', ''   # strip extension if present
        $candidates = @("$base.exe", "$base.com")
    }
    else {
        # Linux / macOS: strip .exe / .com if present, use bare name
        $bare = $Name -replace '\.(exe|com)$', ''
        $candidates = @($bare)
    }

    # ── Walk every directory in $env:PATH ────────────────────────────────────
    $pathDirs = $env:PATH -split ([System.IO.Path]::PathSeparator)   # ';' on Win, ':' on Unix

    foreach ($dir in $pathDirs) {
        if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) {
            continue    # skip empty or non-existent entries
        }

        foreach ($candidate in $candidates) {
            $full = Join-Path $dir $candidate
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                Write-Verbose "Found: $full"
                return [PSCustomObject]@{
                    Found    = $true
                    Name     = $candidate
                    FullPath = $full
                }
            }
        }
    }

    Write-Verbose "'$Name' was not found in any PATH directory."
    return [PSCustomObject]@{
        Found    = $false
        Name     = $Name
        FullPath = $null
    }
}

Export-ModuleMember -Function Test-ExecutableInPath
