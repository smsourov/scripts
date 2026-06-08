# The Code

- [x] Vibe coded

- [ ] Vibe coded and manually modified

- AI model
    
    - [x] ChatGPT
    - [ ] Claude
    - [ ] Gemini
    - [ ] Qwen
    - [ ] Deepseek

- [ ] Hand typed

- [x] Tested and verified

# About

A simple powershell program to add a directory in the Path variable. The benefit of using this script that it will notifiy the user if the directory is already present in the PATH and in which path the directory is present.

# Parameters

- `-Target`: In which path the directory will be added. It accepts `user` and `system`. By default, `user` is used. For the system path, the script has to be run as admin. If not, in the runtime, a temporary script will be generated and will be asked to run it as admin.
- `-Directory`: The directory that should be added. Use quotes.

# Examples

## Add a directory in the user path

```powershell
Add-ToPath -Directory "D:\Workstation\"
```

```powershell
Add-ToPath -Target user -Directory "D:\Workstation\"
```

## Add a directory in the system path

```powershell
Add-ToPath -Target system -Directory "D:\Workstation\"
```

> `random_name_generator.ps1` is required if the admin previledge is required in the runtime.
