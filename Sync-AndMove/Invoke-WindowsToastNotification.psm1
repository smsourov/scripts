function Invoke-WindowsToastNotification {
    <#
    .SYNOPSIS
        Sends a Windows 10/11 toast notification from PowerShell 7.

    .DESCRIPTION
        Displays a native Windows toast notification by delegating to PowerShell 5.1,
        which has full WinRT support. No external modules required.
        Supports titles, messages, buttons, sounds, icons, duration, and scenarios.

    .PARAMETER Title
        The bold heading text of the notification.

    .PARAMETER Message
        The main body text of the notification.

    .PARAMETER Detail
        Optional third line of smaller detail text.

    .PARAMETER AppId
        The AUMID of the app the notification appears to come from.
        Defaults to PowerShell 5.1's registered ID.
        Use Get-StartApps to find other AUMIDs.

    .PARAMETER Duration
        How long the toast stays on screen.
        'Short' = ~7 seconds, 'Long' = ~25 seconds.
        Default: Short.

    .PARAMETER Sound
        Notification sound to play. Use 'Silent' for no sound.
        Default: Default.

    .PARAMETER Scenario
        Controls toast behavior and urgency styling.
        'Default'   : Standard notification.
        'Alarm'     : Stays on screen until dismissed.
        'Reminder'  : Stays on screen until dismissed.
        'IncomingCall' : Incoming call style, stays until dismissed.
        Default: Default.

    .PARAMETER LogoImagePath
        Full path to a PNG/JPG image to show as the toast icon (square, ~48x48px).
        Supports local file paths only.

    .PARAMETER HeroImagePath
        Full path to a PNG/JPG image to show as a wide banner inside the toast (~364x180px).
        Supports local file paths only.

    .PARAMETER Buttons
        An array of hashtables defining action buttons.
        Each hashtable must have 'Label' and 'Arguments' keys.
        Maximum 5 buttons.
        Example: @(@{ Label = 'Open'; Arguments = 'open' }, @{ Label = 'Dismiss'; Arguments = 'dismiss' })

    .PARAMETER ProgressBar
        If specified, shows a progress bar in the notification.
        Pass a hashtable with keys: Title, Value (0.0-1.0), Status, ValueString.
        Example: @{ Title = 'Uploading'; Value = 0.7; Status = 'In progress...'; ValueString = '70%' }

    .PARAMETER Silent
        Suppress all sound. Equivalent to -Sound Silent.

    .PARAMETER PassThru
        Returns the generated toast XML string instead of displaying the notification.
        Useful for debugging.

    .EXAMPLE
        Invoke-WindowsToastNotification -Title "Hello" -Message "World"

    .EXAMPLE
        Invoke-WindowsToastNotification `
            -Title "Build Complete" `
            -Message "0 errors, 2 warnings" `
            -Detail "Finished in 4.2s" `
            -Sound "Mail" `
            -Duration Long

    .EXAMPLE
        Invoke-WindowsToastNotification `
            -Title "Deploy Ready" `
            -Message "Production build is ready to ship." `
            -Buttons @(
                @{ Label = "Open Dashboard"; Arguments = "open_dashboard" },
                @{ Label = "Dismiss";        Arguments = "dismiss"        }
            )

    .EXAMPLE
        Invoke-WindowsToastNotification `
            -Title "File Upload" `
            -Message "Uploading report.pdf to SharePoint..." `
            -ProgressBar @{ Title = "Uploading"; Value = 0.65; Status = "In progress..."; ValueString = "65%" }

    .EXAMPLE
        Invoke-WindowsToastNotification `
            -Title "Reminder" `
            -Message "Team standup in 5 minutes." `
            -Scenario Reminder `
            -Sound Reminder

    .EXAMPLE
        # Use Windows Terminal's App ID instead of PowerShell's
        Invoke-WindowsToastNotification `
            -Title "Done" `
            -Message "Script finished." `
            -AppId "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"

    .EXAMPLE
        # Preview the XML without firing the notification
        Invoke-WindowsToastNotification -Title "Test" -Message "Preview only" -PassThru

    .NOTES
        Author  : Generated for PowerShell 7
        Requires: Windows 10 or later, PowerShell 5.1 present at default path
        WinRT toast notifications are delivered via a hidden PS5.1 subprocess.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter()]
        [string] $Detail,

        [Parameter()]
        [string] $AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe',

        [Parameter()]
        [ValidateSet('Short', 'Long')]
        [string] $Duration = 'Short',

        [Parameter()]
        [ValidateSet('Default', 'IM', 'Mail', 'Reminder', 'SMS', 'Alarm', 'Alarm2',
            'Alarm3', 'Alarm4', 'Alarm5', 'Alarm6', 'Alarm7', 'Alarm8',
            'Alarm9', 'Alarm10', 'Call', 'Call2', 'Call3', 'Call4',
            'Call5', 'Call6', 'Call7', 'Call8', 'Call9', 'Call10', 'Silent')]
        [string] $Sound = 'Default',

        [Parameter()]
        [ValidateSet('Default', 'Alarm', 'Reminder', 'IncomingCall')]
        [string] $Scenario = 'Default',

        [Parameter()]
        [ValidateScript({
                if ($_ -and -not (Test-Path $_)) { throw "LogoImagePath '$_' does not exist." }
                $true
            })]
        [string] $LogoImagePath,

        [Parameter()]
        [ValidateScript({
                if ($_ -and -not (Test-Path $_)) { throw "HeroImagePath '$_' does not exist." }
                $true
            })]
        [string] $HeroImagePath,

        [Parameter()]
        [ValidateScript({
                if ($_ -and -not (Test-Path $_)) { throw "InlineImagePath '$_' does not exist." }
                $true
            })]
        [string] $InlineImagePath,

        [Parameter()]
        [ValidateScript({
                if ($_.Count -gt 5) { throw "A maximum of 5 buttons is supported." }
                foreach ($btn in $_) {
                    if (-not $btn.Label) { throw "Each button hashtable must have a 'Label' key." }
                    if (-not $btn.Arguments) { throw "Each button hashtable must have an 'Arguments' key." }
                }
                $true
            })]
        [hashtable[]] $Buttons,

        [Parameter()]
        [ValidateScript({
                $keys = $_.Keys
                foreach ($required in @('Title', 'Value', 'Status', 'ValueString')) {
                    if ($required -notin $keys) { throw "ProgressBar hashtable must contain key '$required'." }
                }
                if ($_.Value -lt 0 -or $_.Value -gt 1) { throw "ProgressBar Value must be between 0.0 and 1.0." }
                $true
            })]
        [hashtable] $ProgressBar,

        [Parameter()]
        [switch] $Silent,

        [Parameter()]
        [switch] $PassThru
    )

    #region ── Prerequisite check ────────────────────────────────────────────────
    $ps51Path = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $ps51Path)) {
        throw "PowerShell 5.1 not found at '$ps51Path'. This function requires PS5.1 to send WinRT toast notifications."
    }
    #endregion

    #region ── Build toast XML ───────────────────────────────────────────────────
    $scenarioAttr = if ($Scenario -ne 'Default') { " scenario=`"$($Scenario.ToLower())`"" } else { '' }
    $durationAttr = " duration=`"$($Duration.ToLower())`""

    # Visual binding
    $visualXml = "<text>$([System.Security.SecurityElement]::Escape($Title))</text>`n"
    $visualXml += "      <text>$([System.Security.SecurityElement]::Escape($Message))</text>`n"

    if ($Detail) {
        $visualXml += "      <text placement=`"attribution`">$([System.Security.SecurityElement]::Escape($Detail))</text>`n"
    }

    if ($InlineImagePath) {
        $visualXml += "      <image src=`"file:///$($InlineImagePath.Replace('\','/'))`" placement=`"inline`"/>`n"
    }

    if ($LogoImagePath) {
        $visualXml += "      <image placement=`"appLogoOverride`" hint-crop=`"circle`" src=`"file:///$($LogoImagePath.Replace('\','/'))`"/>`n"
    }

    if ($HeroImagePath) {
        $visualXml += "      <image placement=`"hero`" src=`"file:///$($HeroImagePath.Replace('\','/'))`"/>`n"
    }

    if ($ProgressBar) {
        $pbValue = [string]$ProgressBar.Value
        $pbTitle = [System.Security.SecurityElement]::Escape($ProgressBar.Title)
        $pbStatus = [System.Security.SecurityElement]::Escape($ProgressBar.Status)
        $pbValStr = [System.Security.SecurityElement]::Escape($ProgressBar.ValueString)
        $visualXml += "      <progress title=`"$pbTitle`" value=`"$pbValue`" valueStringOverride=`"$pbValStr`" status=`"$pbStatus`"/>`n"
    }

    # Actions (buttons)
    $actionsXml = ''
    if ($Buttons) {
        $actionsXml = "`n  <actions>`n"
        foreach ($btn in $Buttons) {
            $label = [System.Security.SecurityElement]::Escape($btn.Label)
            $args = [System.Security.SecurityElement]::Escape($btn.Arguments)
            $actionsXml += "    <action content=`"$label`" arguments=`"$args`" activationType=`"foreground`"/>`n"
        }
        $actionsXml += "  </actions>"
    }

    # Audio
    $audioXml = if ($Silent -or $Sound -eq 'Silent') {
        "`n  <audio silent=`"true`"/>"
    }
    else {
        "`n  <audio src=`"ms-winsoundevent:Notification.$Sound`"/>"
    }

    # Assemble full XML
    $toastXml = @"
<toast$durationAttr$scenarioAttr>
  <visual>
    <binding template="ToastGeneric">
      $visualXml
    </binding>
  </visual>$actionsXml$audioXml
</toast>
"@
    #endregion

    #region ── PassThru ──────────────────────────────────────────────────────────
    if ($PassThru) {
        return $toastXml
    }
    #endregion

    #region ── Fire notification via PS5.1 ───────────────────────────────────────
    if ($PSCmdlet.ShouldProcess("Windows Toast Notification", "Show '$Title'")) {

        $ps51Script = @"
try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null

    `$AppId   = '$($AppId.Replace("'","''"))'
    `$XmlDoc  = New-Object Windows.Data.Xml.Dom.XmlDocument
    `$XmlDoc.LoadXml('$($toastXml.Replace("'","''"))')
    `$Toast   = New-Object Windows.UI.Notifications.ToastNotification `$XmlDoc
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(`$AppId).Show(`$Toast)
} catch {
    exit 1
}
"@

        $encoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($ps51Script)
        )

        $process = Start-Process `
            -FilePath    $ps51Path `
            -ArgumentList "-NoProfile -NonInteractive -EncodedCommand $encoded" `
            -WindowStyle Hidden `
            -PassThru `
            -Wait

        if ($process.ExitCode -ne 0) {
            Write-Warning "Toast notification may have failed. PS5.1 process exited with code $($process.ExitCode)."
        }
        else {
            Write-Verbose "Toast notification sent: '$Title'"
        }
    }
    #endregion
}

Export-ModuleMember -Function Invoke-WindowsToastNotification
