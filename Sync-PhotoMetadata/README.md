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

A script to modify an image file. It either writes the date time data to the image file or renames the image file based on its date time data.

# Parameters

- `-Directory`: The directory where the images are located.
- `-List`: A list of directories in a text file where the images are located.
- `-ModifyFilename`: Rename the image files according to their date time data to `YYYYMMDD_HHMMSS`.
- `-ModifyExifDatetime`: Modify the date time data according to the filename. In order for this parameter to work, the filename has to be in `YYYYMMDD_HHMMSS` format.
- `-CopyToDirectory`: Copy the modified files to a directory.
- `-MoveToDirectory`: Move the modified files to a directory.
- `-MissingExifDatetimeOnly`: Instead of modifying date time data for all files, only modify those where the date time data is absent.
- `-WrongFilenameOnly`: Instead of modifying filename for all files, only modify those where the filename is wrong.
- `-ExifToolLocation`: Location of the `exiftool.exe`. If you have `exiftool(-k).exe`, just rename it to `exiftool.exe` otherwise the program wont work.
- `-Confirm`: Automatically confirm the `-ModifyFilename`, `-ModifyExifDatetime`, `-MissingExifDatetimeOnly`, `-WrongFilenameOnly`, `-MoveToDirectory`, `-CopyToDirectory` tasks. Normally a user confirmation is required.

# Examples

> I got tired. You find out.
