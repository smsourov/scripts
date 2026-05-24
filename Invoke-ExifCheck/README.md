# The Code

- [ ] Vibe coded

- [x] Vibe coded and manually modified

- AI model
    
    - [x] ChatGPT
    - [x] Claude
    - [ ] Gemini
    - [ ] Qwen
    - [ ] Deepseek

- [ ] Hand typed

- [x] Tested and verified

# About

A script to check the existance of of an EXIF data and EXIF:DateTime data.

# Parameters

- `-Directory`: The directory where the images will be checked.
- `-Lists`: A list of directories where the images will be checked.
- `-CheckExifPresenceOnly`: Only list those images that contains at least one exif data. By default, this parameter is used.
- `-CheckExifDatePresenceOnly`: Only list those images that contains EXIF:DateTime data.
- `-CheckExifAbsenceOnly`: Only list those images that doesn't contain any exif data.
- `-CheckExifDateAbsenceOnly`: Only list those images that does't contain EXIF:DateTime data.
- `-MoveToDirectory`: This is an optional parameter. The directory where the list of images will moved to.
- `-CopyToDirectory`: This is an optional parameter. The directory where the list of images will copied to.
- `-AllCores`: This is an optional parameter. It will get the amount of cores you processor have and it will process that amount of files at a time.
- `-AllLogicalProcessors`: This is an optional parameter. It will get the amount of logical processors you processor have and it will process that amount of files at a time.
- `-MultiThread`: This is an optional parameter. With this you can manually define how many files to process at a time.
- `-MagickLocation`: This is an optional parameter. The location of `magick.exe` binary.
- `-Confirm`: This is an optional parameter. Using this parameter automatically confirms the move/copy task. Normally `-MoveToDirectory` and `-CopyToDirectory` requires a user confirmation.
- `-Force`: This is an optional parameter. Dangerous. If a file is present in the targeted directory, it `-MoveToDirectory`/`-CopyToDirectory` overwrites that file. If you want to use this parameter, you have to manually edit the script and change the value of `$safemode` to `$false`.
- `-Help`: Print this messages.

# Examples

## Checking a directory

```powershell
Invoke-ExifCheck -Directory "D:\images\" -MagickLocation "D:\magick.exe"
```

```powershell
Invoke-ExifCheck -Directory "D:\images\" -MagickLocation "D:\magick.exe" -CheckExifPresenceOnly
```

## Check for EXIF:DateTime

```powershell
Invoke-ExifCheck -Directory "D:\images\" -MagickLocation "D:\magick.exe" -CheckExifDatePresenceOnly
```

> Same syntax is applicable for `-CheckExifAbsenceOnly`, `-CheckExifDateAbsenceOnly`.

## Copying to a directory

```powershell
Invoke-ExifCheck -Directory "D:\images\" -MagickLocation "D:\magick.exe" -CopyToDirectory "E:\images\"
```

> Same syntax is applicable for `-MoveToDirectory`.

## Processing multiple files

```powershell
Invoke-ExifCheck -Directory "D:\images\" -MagickLocation "D:\magick.exe" -AllCores
```

```powershell
Invoke-ExifCheck -Directory "D:\images\" -MagickLocation "D:\magick.exe" -AllLogicalProcessors
```

```powershell
Invoke-ExifCheck -Directory "D:\images\" -MagickLocation "D:\magick.exe" -MultiThread 5
```

## Automatically confirm

```powershell
Invoke-ExifCheck -Directory "D:\images\" -MagickLocation "D:\magick.exe" -CopyToDirectory "E:\images\" -Confirm
```
