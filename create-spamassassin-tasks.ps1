# ==============================================================================
# Author  : Mikhail Deynekin <mid1977@gmail.com> | https://deynekin.com
# GitHub  : https://github.com/paulmann
# Project : SpamAssassin for Windows — PowerShell 7 Automation Suite
# File    : create-spamassassin-tasks.ps1
# Purpose : Register two Windows Scheduled Tasks:
#             1. SpamAssassin-spamd-Startup  -- launches spamd at every boot
#             2. SpamAssassin-Update-Daily   -- runs sa-update once per day
#           Run this script ONCE from PowerShell 7 as Administrator.
#           Re-running is safe: -Force overwrites existing tasks.
# ==============================================================================

[CmdletBinding()]
param(
    # Directory containing start-spamd.ps1 and update-spamassassin.ps1.
    # Update this if you store the scripts in a different location.
    [string]$ScriptsRoot = 'C:\mail\scripts\spam',

    # Full path to the PowerShell 7 executable.
    # Run: (Get-Command pwsh).Source   to find the correct path on your machine.
    [string]$PwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe',

    # Display name for the startup task (shown in Task Scheduler UI).
    [string]$StartupTaskName = 'SpamAssassin-spamd-Startup',

    # Display name for the daily update task.
    [string]$UpdateTaskName = 'SpamAssassin-Update-Daily',

    # Time of day for the daily sa-update run (24-hour HH:mm format).
    # Choose a low-traffic window. Default: 03:30.
    [string]$UpdateTime = '03:30',

    # Task Scheduler folder (subfolder of \) where tasks will be stored.
    # Keeps SpamAssassin tasks organized and separate from other tasks.
    [string]$TaskFolder = '\SpamAssassin'
)

$ErrorActionPreference = 'Stop'

# --- Derived paths -----------------------------------------------------------
$StartScript  = Join-Path $ScriptsRoot 'start-spamd.ps1'
$UpdateScript = Join-Path $ScriptsRoot 'update-spamassassin.ps1'

# === PREFLIGHT ================================================================

foreach ($file in @($PwshPath, $StartScript, $UpdateScript)) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Required file not found: ${file}`nVerify paths before registering tasks."
    }
}

# === CREATE TASK FOLDER =======================================================

$schedSvc = New-Object -ComObject 'Schedule.Service'
$schedSvc.Connect()
$rootFolder = $schedSvc.GetFolder('\')

try {
    $rootFolder.GetFolder($TaskFolder) | Out-Null
} catch {
    $rootFolder.CreateFolder($TaskFolder) | Out-Null
    Write-Host "[INFO] Created Task Scheduler folder: ${TaskFolder}"
}

# === SHARED PRINCIPAL =========================================================
# Run as SYSTEM with highest privileges so spamd starts before any user logs in.
$principal = New-ScheduledTaskPrincipal `
    -UserId    'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel  Highest

# ==============================================================================
# TASK 1: Start spamd at Windows startup
# ==============================================================================

$startupArg    = "-NoProfile -ExecutionPolicy Bypass -File `"${StartScript}`""
$startupAction = New-ScheduledTaskAction `
    -Execute          $PwshPath `
    -Argument         $startupArg `
    -WorkingDirectory $ScriptsRoot

$startupTrigger = New-ScheduledTaskTrigger -AtStartup

$startupSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances  IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask `
    -TaskName    $StartupTaskName `
    -TaskPath    $TaskFolder `
    -Action      $startupAction `
    -Trigger     $startupTrigger `
    -Principal   $principal `
    -Settings    $startupSettings `
    -Description 'Starts SpamAssassin spamd.exe at Windows boot (no --daemonize; POSIX-safe).' `
    -Force | Out-Null

Write-Host "[OK] Registered: ${TaskFolder}\${StartupTaskName}"

# ==============================================================================
# TASK 2: Daily sa-update + spamd restart
# ==============================================================================

$updateArg    = "-NoProfile -ExecutionPolicy Bypass -File `"${UpdateScript}`""
$updateAction = New-ScheduledTaskAction `
    -Execute          $PwshPath `
    -Argument         $updateArg `
    -WorkingDirectory $ScriptsRoot

$updateTrigger = New-ScheduledTaskTrigger -Daily -At $UpdateTime

$updateSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances  IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask `
    -TaskName    $UpdateTaskName `
    -TaskPath    $TaskFolder `
    -Action      $updateAction `
    -Trigger     $updateTrigger `
    -Principal   $principal `
    -Settings    $updateSettings `
    -Description "Runs sa-update daily at ${UpdateTime} and restarts spamd on success." `
    -Force | Out-Null

Write-Host "[OK] Registered: ${TaskFolder}\${UpdateTaskName}"

# === NEXT STEPS ===============================================================

Write-Host ''
Write-Host 'All tasks registered successfully.'
Write-Host ''
Write-Host 'Verify:'
Write-Host "  Get-ScheduledTask -TaskPath '${TaskFolder}' | Format-Table TaskName, State"
Write-Host ''
Write-Host 'Run manually:'
Write-Host "  Start-ScheduledTask -TaskPath '${TaskFolder}' -TaskName '${StartupTaskName}'"
Write-Host "  Start-ScheduledTask -TaskPath '${TaskFolder}' -TaskName '${UpdateTaskName}'"
Write-Host ''
Write-Host 'View history: Task Scheduler > Task Scheduler Library > SpamAssassin'
