function ytdlpFunction {
	<#
.SYNOPSIS
    A PowerShell wrapper around yt-dlp for downloading videos with fine-grained control.

.DESCRIPTION
    Invokes yt-dlp via Python with a structured set of parameters covering format selection,
    subtitle handling, thumbnail embedding, metadata, fragment control, and more.
    Supports an interactive mode for manually picking video/audio stream IDs, and a
    CustomCommands preset that enables a sensible defaults bundle in one switch.

    Requires Python (py) and yt-dlp to be accessible. FFmpeg and FFprobe are validated
    against PATH when FFmpegDirLocation is provided.

.PARAMETER Version
    Prints the installed yt-dlp version and exits.

.PARAMETER Update
    Updates yt-dlp to the latest release and exits.

.PARAMETER Link
    The URL of the video or playlist to download.

.PARAMETER IgnoreErrors
    Continues downloading the next item in a playlist when an error occurs.

.PARAMETER JSRuntimes
    The JavaScript runtime to use. Accepted values: deno, node, quickjs, bun.
    Defaults to 'quickjs'.

.PARAMETER ConcurrentFragments
    Number of fragments to download in parallel. Accepted range: 1–32. Defaults to 1.

.PARAMETER KeepFragments
    Keeps the downloaded fragments on disk after merging.

.PARAMETER RestrictFilenames
    Restricts output filenames to ASCII characters only.

.PARAMETER WindowsFilenames
    Sanitises filenames to be safe on Windows (removes characters like : * ? " < > |).

.PARAMETER Continue
    Resumes a previously interrupted download if partial fragments exist.

.PARAMETER WriteDescription
    Saves the video description to a .description file alongside the video.

.PARAMETER WriteComments
    Saves video comments to a .json file alongside the video.

.PARAMETER CookiesFromBrowser
    Imports cookies from the specified browser to authenticate requests.
    Accepted values: brave, chrome, chromium, edge, firefox, opera, safari, vivaldi, whale.

.PARAMETER WriteThumbnail
    Saves the video thumbnail as a separate image file.
    Note: combining this with EmbedThumbnail will save the video in MKV.

.PARAMETER WriteLink
    Writes a .url/.webloc/.desktop hyperlink file pointing to the original video URL.

.PARAMETER Quiet
    Suppresses yt-dlp terminal output (except errors).

.PARAMETER SkipDownload
    Processes all selected options (metadata, subs, thumbnails) without downloading the video.

.PARAMETER Progress
    Forces the progress bar to display, even when output is redirected or quiet mode is on.

.PARAMETER ConsoleTitle
    Sets the terminal window title to the name of the video being downloaded.

.PARAMETER VideoID
    The format ID for the video stream. Defaults to '248' (YouTube 1080p VP9).
    Run with -ListFormats or -Interactive to discover available IDs.

.PARAMETER AudioID
    The format ID for the audio stream. Defaults to '140' (YouTube 128k AAC).
    Run with -ListFormats or -Interactive to discover available IDs.

.PARAMETER VideoMultistreams
    Allows multiple video streams to be merged into the output file.

.PARAMETER AudioMultistreams
    Allows multiple audio streams to be merged into the output file.

.PARAMETER CheckFormats
    Verifies that the selected VideoID and AudioID formats are actually accessible before downloading.

.PARAMETER CheckAllFormats
    Verifies that every detected format is accessible. Slower than -CheckFormats.

.PARAMETER ListFormats
    Lists all available video and audio format IDs for the given link and exits.

.PARAMETER MergeOutputFormat
    The container format to use when merging video and audio streams.
    Accepted values: avi, flv, mkv, mov, mp4, webm. Defaults to 'mkv'.

.PARAMETER WriteSubs
    Downloads subtitles as separate files alongside the video.

.PARAMETER SubLangs
    Comma-separated list of subtitle language codes to download (e.g. 'en,fr').
    Defaults to 'all'. Only applies when -WriteSubs or -EmbedSubs is used.

.PARAMETER KeepVideo
    Retains the original video file after post-processing (e.g. remuxing or merging).

.PARAMETER EmbedSubs
    Embeds subtitles directly into the output video file.

.PARAMETER EmbedThumbnail
    Embeds the thumbnail as cover art inside the output video file.

.PARAMETER EmbedMetadata
    Embeds video metadata (title, uploader, description, etc.) into the output file.

.PARAMETER EmbedChapters
    Embeds chapter markers from the video page into the output file.

.PARAMETER FFmpegDirLocation
    Full path to the directory containing ffmpeg and ffprobe binaries.
    When set, both executables are validated against PATH before proceeding.

.PARAMETER ConvertThumbnails
    Converts the thumbnail to the specified format after downloading.
    Accepted values: jpg, png, webp, none. Defaults to 'jpg'.

.PARAMETER YTDLPLocation
    Full path to the yt-dlp script or executable (without extension).

.PARAMETER Interactive
    Lists available format IDs first, then prompts you to manually enter
    VideoID and AudioID before proceeding with the download.

.PARAMETER CustomCommands
    Activates a preset bundle of commonly used options:
    Continue, WriteDescription, WindowsFilenames, Interactive, WriteThumbnail,
    ConcurrentFragments=8, Progress, ConsoleTitle, VideoMultistreams,
    AudioMultistreams, CheckFormats, WriteSubs, EmbedSubs, EmbedThumbnail,
    EmbedMetadata, EmbedChapters, ConvertThumbnails=jpg.

.EXAMPLE
    ytdlpFunction -Link "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    Downloads the video using default format IDs (248+140) into an MKV container.

.EXAMPLE
    ytdlpFunction -Link "https://www.youtube.com/watch?v=dQw4w9WgXcQ" -Interactive
    Lists all available format IDs, then prompts for VideoID and AudioID before downloading.

.EXAMPLE
    ytdlpFunction -Link "https://www.youtube.com/watch?v=dQw4w9WgXcQ" -CustomCommands
    Downloads using the full preset bundle with interactive format selection.

.EXAMPLE
    ytdlpFunction -Link "https://www.youtube.com/watch?v=dQw4w9WgXcQ" -EmbedSubs -EmbedMetadata -EmbedChapters -MergeOutputFormat mp4
    Downloads into MP4 with subtitles, metadata, and chapters embedded.

.EXAMPLE
    ytdlpFunction -Version
    Prints the installed yt-dlp version.

.EXAMPLE
    ytdlpFunction -Link "https://www.youtube.com/watch?v=dQw4w9WgXcQ" -ListFormats
    Lists all available format IDs for the video without downloading.

.NOTES
    Depends on: Python (py), yt-dlp, FFmpeg, FFprobe.
    Tested on: PowerShell 7+. Compatible with Windows PowerShell 5.1.
    FFmpeg/FFprobe are looked up in PATH regardless of FFmpegDirLocation —
    ensure they are on PATH or adjust the check accordingly.
#>
	#region parameters
	param (
		# YTDLP version
		[Parameter()]
		[switch]
		$Version,
		# Update YTDLP
		[Parameter()]
		[switch]
		$Update,
		# Video Link
		[Parameter()]
		[string]
		$Link,
		# Ignore erros
		[Parameter()]
		[switch]
		$IgnoreErrors,
		# JS runtime
		[ValidateSet("deno", "node", "quickjs", "bun")]
		[string]
		$JSRuntimes = "quickjs",
		# Number of fragments
		[ValidateRange(1, 32)]
		[int]
		$ConcurrentFragments = 1,
		# Keep video fragments
		[Parameter()]
		[switch]
		$KeepFragments,
		# Restrict filenames
		[Parameter()]
		[switch]
		$RestrictFilenames,
		# Windows filenames only
		[Parameter()]
		[switch]
		$WindowsFilenames,
		# Resume previous interrupted download
		[Parameter()]
		[switch]
		$Continue,
		# Write video description given in the website
		[Parameter()]
		[switch]
		$WriteDescription,
		# Write video comments
		[Parameter()]
		[switch]
		$WriteComments,
		# Import cookies from browser (Firefox works)
		[ValidateSet("brave", "chrome", "chromium", "edge", "firefox", "opera", "safari", "vivaldi", "whale")]
		[string]
		$CookiesFromBrowser,
		# Write video thumbnail (using this will save the video in MKV)
		[Parameter()]
		[switch]
		$WriteThumbnail,
		# Write video hyperlink
		[Parameter()]
		[switch]
		$WriteLink,
		# Don't show extra informations in the terminal
		[Parameter()]
		[switch]
		$Quiet,
		# Don't download anything
		[Parameter()]
		[switch]
		$SkipDownload,
		# Show progress
		[Parameter()]
		[switch]
		$Progress,
		# Change the console title to media name
		[Parameter()]
		[switch]
		$ConsoleTitle,
		# Select video ID (YouTube only)
		[Parameter()]
		[string]
		$VideoID = "248",
		# Select audio ID (YouTube only)
		[Parameter()]
		[string]
		$AudioID = "140",
		# Output file should contain multiple video
		[Parameter()]
		[switch]
		$VideoMultistreams,
		# Output file should contain multiple audio
		[Parameter()]
		[switch]
		$AudioMultistreams,
		# Verify whether the selected formats are accessible (YouTube only)
		[Parameter()]
		[switch]
		$CheckFormats,
		# Verify all of the formats that are detected are accessible (YouTube only)
		[Parameter()]
		[switch]
		$CheckAllFormats,
		# List video and audio IDs (YouTube only)
		[Parameter()]
		[switch]
		$ListFormats,
		# Select output format (works if the media file have multiple audio/video/thumbnail)
		[ValidateSet("avi", "flv", "mkv", "mov", "mp4", "webm")]
		[string]
		$MergeOutputFormat = "mkv",
		# Save the subtitles seperately
		[Parameter()]
		[switch]
		$WriteSubs,
		# Select subtitle language
		[Parameter()]
		[string]
		$SubLangs = "all",
		# Keep the temporary video file
		[Parameter()]
		[switch]
		$KeepVideo,
		# Include the subtitles in the video
		[Parameter()]
		[switch]
		$EmbedSubs,
		# Include the thumbnail in the video
		[Parameter()]
		[switch]
		$EmbedThumbnail,
		# Include the metadata in the video
		[Parameter()]
		[switch]
		$EmbedMetadata,
		# Include the video chapters in the video
		[Parameter()]
		[switch]
		$EmbedChapters,
		# Define the ffmpeg/ffprobe directory location
		[Parameter()]
		[string]
		$FFmpegDirLocation,
		# Conver the thumbnail
		[ValidateSet("jpg", "png", "webp", "none")]
		[string]
		$ConvertThumbnails = "jpg",
		# Define yt-dlp location
		[Parameter()]
		[string]
		$YTDLPLocation,
		# Manually select video and audio ID
		[Parameter()]
		[switch]
		$Interactive,
		# Use predefined commands
		[Parameter()]
		[switch]
		$CustomCommands
	)
	#endregion: parameters

	# prepare the arguments variable
	$arguments = @()

	if ($CustomCommands) {
		$Continue = $true
		$WriteDescription = $true
		$WindowsFilenames = $true
		$Interactive = $true
		$WriteThumbnail = $true
		$ConcurrentFragments = 8
		$Progress = $true
		$ConsoleTitle = $true
		$VideoMultistreams = $true
		$AudioMultistreams = $true
		$CheckFormats = $true
		$WriteSubs = $true
		$EmbedSubs = $true
		$EmbedThumbnail = $true
		$EmbedMetadata = $true
		$EmbedChapters = $true
		$ConvertThumbnails = "jpg"
	}

	if ($FFmpegDirLocation) {
		Import-Module "$PSScriptRoot/Test-ExecutableInPath.psm1" -Function Test-ExecutableInPath
		$ffmpegResult = Test-ExecutableInPath -Name 'ffmpeg'
		$ffprobeResult = Test-ExecutableInPath -Name 'ffprobe'

		if (!$ffmpegResult.Found -and !$ffprobeResult.Found) {
			Write-Error "FFMpeg and FFProbe was not found"
			return
		}
		elseif (!$ffmpegResult.Found) {
			Write-Error "FFMpeg was not found"
			return
		}
		elseif (!$ffprobeResult.Found) {
			Write-Error "FFProbe was not found"
			return
		}
	}

	if ($Version) {
		$arguments += "--version"
		& py $YTDLPLocation $arguments
		return
	}

	if ($Update) {
		$arguments += "--update"
		& py $YTDLPLocation $arguments
		return
	}

	if ($IgnoreErrors) {
		$arguments += "--ignore-errors"
	}

	if ($JSRuntimes) {
		# Include the QuickJS runtime
		$arguments += "--js-runtimes"
		$arguments += "$($JSRuntimes)"
	}

	# Define how many fragments to download in each moment
	$arguments += "--concurrent-fragments"
	$arguments += "$($ConcurrentFragments)"


	if ($KeepFragments) {
		$arguments += "--keep-fragments"
	}

	if ($RestrictFilenames) {
		$arguments += "--restrict-filenames"
	}

	if ($WindowsFilenames) {
		# Make the file names safe for Windows system
		$arguments += "--windows-filenames"
	}

	if ($Continue) {
		# Add download resume support
		$arguments += "--continue"
	}

	if ($WriteDescription) {
		# Write the video description
		$arguments += "--write-description"
	}

	if ($WriteComments) {
		$arguments += "--write-comments"
	}

	if ($CookiesFromBrowser) {
		$arguments += "--cookies-from-browser"
		$arguments += "$($CookiesFromBrowser)"
	}

	if ($WriteThumbnail) {
		# Write the video thumbnail
		$arguments += "--write-thumbnail"
	}

	if ($WriteLink) {
		# Write a link file for that content
		$arguments += "--write-link"
	}

	if ($Quiet) {
		# Activate quiet mode
		$arguments += "--quiet"
	}

	if ($SkipDownload) {
		$arguments += "--skip-download"
	}

	if ($Progress) {
		$arguments += "--progress"
	}

	if ($ConsoleTitle) {
		# Optionally change the console title to video title
		$arguments += "--console-title"
	}

	# The IDs should be taken/updated before it is included 
	# in the arguments. Otherwise, it will break the
	# program
	if ($Interactive) {
		$arguments += "--list-formats"
		& py $YTDLPLocation $arguments $Link
		$VideoID = Read-Host "Enter VideoID"
		$AudioID = Read-Host "Enter AudioID"
		# Remove the "--list-formats"
		$arguments = $arguments | Where-Object { $_ -ne "--list-formats" }
	}

	# Download specific format
	$arguments += "--format"
	$arguments += "$($VideoID)+$($AudioID)"

	if ($VideoMultistreams) {
		# Allow multiple video to be merged into a single file
		$arguments += "--video-multistreams"
	}

	if ($AudioMultistreams) {
		# Allow multiple audio to be merged into a single file
		$arguments += "--audio-multistreams"
	}

	if ($CheckFormats) {
		# Verify whether the selected formats are available to download
		$arguments += "--check-formats"
	}

	if ($CheckAllFormats) {
		$arguments += "--check-all-formats"
	}

	if ($ListFormats) {
		# & py $YTDLPLocation --js-runtimes quickjs --list-formats $Link
		$arguments += "--list-formats"
		& py $YTDLPLocation $arguments --list-formats $Link
		return
	}

	# Define the container format
	$arguments += "--merge-output-format"
	$arguments += "$($MergeOutputFormat)"

	if ($WriteSubs) {
		# Download the subtitles
		$arguments += "--write-subs"
	}

	# Download subtitle of all languages
	$arguments += "--sub-langs"
	$arguments += "$($SubLangs)"
	
	if ($KeepVideo) {
		# Keep the temporary video file
		$arguments += "--keep-video"
	}

	if ($EmbedSubs) {
		# Merge the subtitles to the video
		$arguments += "--embed-subs"
	}

	if ($EmbedThumbnail) {
		# Merge the thumbnail to the video
		$arguments += "--embed-thumbnail"
	}
	
	if ($EmbedMetadata) {
		# Merge the metadata to the video
		$arguments += "--embed-metadata"
	}
	
	if ($EmbedChapters) {
		# Merge the chapters to the video
		$arguments += "--embed-chapters"
	}
	
	# Define ffmpeg location
	$arguments += "--ffmpeg-location"
	$arguments += "$($FFmpegDirLocation)"

	if ($ConvertThumbnails) {
		# Convert the thumbnail from WebP to JPG
		$arguments += "--convert-thumbnails"
		$arguments += "$($ConvertThumbnails)"
	}

	# Check yt-dlp file existence
	if ($YTDLPLocation) {
		$YTDLPResult = Test-Path -Path $YTDLPLocation
		if (!$YTDLPResult) {
			Write-Error "YT-DLP was not found"
			return
		}
	}
	

	& py $YTDLPLocation $arguments $Link
}

Export-ModuleMember -Function ytdlpFunction
