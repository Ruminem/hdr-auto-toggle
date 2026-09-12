# install-task.ps1 - run "hdr.ps1 watch" hidden at every logon. Re-run to update.
# Remove with: Unregister-ScheduledTask -TaskName hdr-auto-toggle -Confirm:$false
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'hdr.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" watch' -f $script)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName 'hdr-auto-toggle' -Action $action -Trigger $trigger `
    -Settings $settings -Force | Out-Null
'registered. start it now with: Start-ScheduledTask -TaskName hdr-auto-toggle'
