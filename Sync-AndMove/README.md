
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

A simple program to do some post-transfer task when a transfer in Syncthing is completed.

# Parameters

No parameters.

# Examples

```powershell
Sync-AndMove
```

# Working Mechanism

Assuming you are cloning this repository. You'll see two powershell files in this directory.

* `Sync-AndMove.ps1`
* `Process-Files.ps1`

Two powershell files have two different task.

## `Sync-AndMove.ps1`

This powershell file monitors whether any transfer is going on or not. After a transfer is completed, it makes a list as a text file and passes that to `Process-Files.ps1`.

It has several variables and it is the top of the code. Among them, only the following variables are important:

* `$ST_BASE_URL`: You have to give your Syncthing server address with the port number. For example: `http:127.0.0.1:8384`.
* `ST_API_KEY`: There is no authentication using the script. So, you need the API key of your server. You can get your API key by going to your Syncthing server. From there, go to Actions > Settings. You'll see the API key of your server in there.

You can see that there is no way to set a folder to monitor. It is designed in that way. After setting the variables, you have to run the script normally 2 times.

### Adding folders

On the first run, you will get an error saying `Created watch_list.txt. Please add your Syncthing folder IDs and restart the script.` and the `watch_list.txt` file will be created.

You will see a content like this in the `watch_list.txt` file.

```text
# Syncthing Folder Watch List
# Add one Syncthing folder ID per line below this comment.
# Folder IDs are shown in the Syncthing Web UI under each folder's label.
# Example:
#   default
#   photos-abc12

```

In the last line, you have to give your Syncthing folder IDs, adding one ID per line.

### Setting the Target Folder

On the second run (or if `targetfolder.txt` is missing), the script will create a `targetfolder.txt` file and exit. The generated file will look like this:

```text
# Target Directory
# Write the full path of the destination folder on the line below this comment.
# Example:  D:\Photos\Imported

```

You must enter the full path of your desired destination folder on the last line.

### Running the Watcher

Once your API key, `watch_list.txt`, and `targetfolder.txt` are configured, run `Sync-AndMove.ps1`. The script will:

- Poll the Syncthing API every few seconds (the default is 10 seconds).
- Wait until all watched folders report an "idle" state.
- Move all top-level files from the watched folders to your configured target directory. You can change this behavior by changing the value of `$ENABLE_MOVE`.
- Create a timestamped manifest file (e.g., `moved_files_<timestamp>.txt`) containing the new file paths.
- Pass this manifest to `Process-Files.ps1` for next-stage processing.
- Each time a sync is complete, the user will receive a notification.

## `Process-Files.ps1`

This script acts as the next-stage processor that receives a manifest of moved files and acts on them. It is automatically called by `Sync-AndMove.ps1`.

- **Default Behavior:** Out of the box, the code includes an example of converting the moved files to `.jxl` format using ImageMagick (`magick.exe`).
- **Customization:** You are expected to replace the code inside the "DO WORK HERE" block with your actual processing logic.
- **Safety Mechanism:** The script reads the manifest file and processes each file. It will only delete the manifest when all work is successfully completed. If the script fails or is killed prematurely, the manifest survives. `Sync-AndMove.ps1` will detect this "stale manifest" and block new batches until you manually review and delete it.

## Logging

Both scripts keep local records of their actions in the same directory:

- `Sync-AndMove.ps1` logs messages to `Sync-AndMove.log`.
- `Process-Files.ps1` logs messages to `Process-Files.log`.

## Known problem

If you have enabled `Ignore Delete` function, the script may function awkwardly.