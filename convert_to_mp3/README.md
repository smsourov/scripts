# The Code

- [x] Vibe coded

- [ ] Vibe coded and manually modified

- AI model
    
    - [ ] ChatGPT
    - [x] Claude
    - [ ] Gemini
    - [ ] Qwen
    - [ ] Deepseek

- [ ] Hand typed

- [x] Tested and verified

# About

Convert a directory of MKV/MP4 files to MP3 file.

## Conversion process

It is assumed that your MKV/MP4 has the following informations:

- Movie name (name of the media in the website)
- Artist (the account that uploaded it)
- Comment (the media link)
- Thumbnail image
- Date (when it was uploaded, YYYYMMDD)
- SRT Subtitle (if it has multilple, the first one will be selected)

## Information mapping

During the conversion, the mp3 informations will be written in the following order

- mp3_title : mkv_movie_name 
- mp3_artist : mkv_artist
- mp3_album : mkv_artist
- mp3_comment : mkv_comment
- mp3_cover_image : mkv_thumbnail_image
- mp3_year : mkv_date
- mp3_lyrics : mkv_lyrics

## Subtitle conversion

Assuming your video has a subtitle like this:

```
1
00:00:01,193 --> 00:00:02,313
a

2
00:00:03,293 --> 00:00:04,520
b

3
00:00:04,947 --> 00:00:06,100
c

4
00:00:08,367 --> 00:00:09,153
d

```

It will converted to this format:

```
[00:01.193]a
[00:02.313]
[00:03.293]b
[00:04.520]
[00:04.947]c
[00:06.100]
[00:08.367]d
[00:09.153]

```

# Dependencies

## Programs

The program cannot do everything by itself. It needs the following programs in the path:

- ffmpeg
- ffprobe

You can download the binaries from [here](https://www.gyan.dev/ffmpeg/builds/). It is recommended to download the latest release `ffmpeg-release-full.7z` version.

## Python module

The following dependency is for the python script only:

- mutagen

A simple `pip` command will install it.

```powershell
py -m pip install mutagen
```


# Parameters

It accepts two unnamed parameters. 
- **Source Directory**: The directory where the MP4/MKV files are located.
- **DESTINATION Directory**: The directory where the converted files will be saved.

# Examples

```powershell
py convert_to_mp3.py "SOURCE_FOLDER" "DESTINATION FOLDER"
```
```powershell
py convert_to_mp3.py "C:\my songs" "D:\my converted songs"
```