Import-Module .\Invoke-WindowsToastNotification.psm1 -Function Invoke-WindowsToastNotification

Invoke-WindowsToastNotification -Title "Syncthing" -Message "Anything" -Detail "A test notification" -AppId "Microsoft.PowerShell_8wekyb3d8bbwe!App"