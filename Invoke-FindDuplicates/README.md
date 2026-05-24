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

Scripts to find duplicates in a folder or in two folders. This directory contains 2 script files, `Invoke-FindDuplicates.ps1` and `Invoke-FindDuplicatesRemove.ps1`. `Invoke-FindDuplicates.ps1` is focused on finding duplicates and `Invoke-FindDuplicatesRemove.ps1` is focused finding duplicates in two folders and removing duplicates.

It detects duplicates by checking their hash SHA256 and MD5. If multiple files contains the same SHA256 and MD5, those are marked as duplicates.

## `Invoke-FindDuplicates.ps1`

# Parameters

- `-Directory1`: This is a mandatory parameter. A directory must be given.
- `-Directory2`: This is an optional parameter. Use this parameter and give the directory if the comparison is going to be done between two directories.
- `-IdentitalTest`: This is an optional parameter. Use this if you just want to know whether 2 directories are identical or not. Without this parameter, it will show a list of files that are identical. With this parameter, it will show a 1 line output.
- `-SingleDirectory`: This is an optional parameter. Use this if you want to find duplicates in a directory.

# Examples

### Compare two diectories

```powershell
Invoke-FindDuplicates -Directory1 "D:\Directory 1\" -Directory2 "E:\Directory 2\"
```

### Identical test

```powershell
Invoke-FindDuplicates -Directory1 "D:\Directory 1\" -Directory2 "E:\Directory 2\" -IdenticalTest
```

### Duplicates in a directory

```powershell
Invoke-FindDuplicates -Directory1 "D:\Directory 1\" -SingleDirectory
```




## `Invoke-FindDuplicatesRemove.ps1`

# Parameters

- `Directory1`: This is a mandatory parameter. A directory must be given.
- `Directory2`: This is an optional parameter. Use this parameter and give the directory if the comparison is going to be done between two directories.

# Examples

### Compare two directories

```powershell
Invoke-FindDuplicates -Directory1 "D:\Directory 1\" -Directory2 "E:\Directory 2\"
```

After finding duplicates, three options will appear.
- `1 = Confirm each file`
- `2 = Confirm in batches`
- `3 = Confirm all at once`

`1` is self explanatory. You have to manually approve/deny deletion of each file. 

In `2`, you have to set a batch size (1-100) and approve/deny deletion of each batch.

In `3`, you have to approve/deny deletion of the entire list of duplicates.
