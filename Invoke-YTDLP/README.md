# The Code

- [ ] Vibe coded

- [x] Vibe coded and manually modified

- AI model
    
    - [ ] ChatGPT
    - [x] Claude
    - [ ] Gemini
    - [ ] Qwen
    - [ ] Deepseek

- [ ] Hand typed

- [x] Tested and verified

# About

A simple powershell module that works as a wrapper for yt-dlp. It's a module so it needs to be used in a powershell file to work. It is recommended to import the script in `Profile.ps1`

```powershell
Import-Module "$PSScriptRoot\Invoke-YTDLP.psm1"
New-Alias yt-dlp ytdlpFunction # To easily use it
```

# Parameters

It contains a good amount of parameters. Not every parameter is used but a good amount that is used normally.

// Todo write parameters and it's workings

# Examples

A normal Example

```sh
yt-dlp -Link "LINK"
```

To manulaly select the formats
```sh
yt-dlp -Interative -Link "LINK"
```

For special case

```sh
yt-dlp -CustomCommands -Link "LINK"
```
