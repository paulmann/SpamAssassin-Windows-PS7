# ==============================================================================
# Author  : Mikhail Deynekin <mid1977@gmail.com> | https://deynekin.com
# GitHub  : https://github.com/paulmann
# Project : SpamAssassin for Windows — PowerShell 7 Automation Suite
# File    : update-spamassassin.ps1
# Purpose : Download and apply the latest SpamAssassin rule updates via
#           sa-update.exe, then restart spamd so new rules take effect.
#           Designed to be triggered daily by Windows Task Scheduler.
# ==============================================================================

[CmdletBinding()]
param(
    # Full path to the SpamAssassin installation directory.
    # Must match the value used in start-spamd.ps1.
    [string]$SaRoot = 'C:\mail\SpamAssasin',

    # Absolute path to start-spamd.ps1.
    # This script is called after a successful rule update to restart spamd.
    [string]$StartScript = 'C:\mail\scripts\spam\start-spamd.ps1',

    # Set to $true to skip GPG signature verification.
    # Use only if GnuPG (Gpg4win) is not installed.
    # WARNING: skipping GPG reduces update security. Install Gpg4win instead.
    [switch]$NoGpg
)

$ErrorActionPreference = 'Stop'

# --- Derived paths -----------------------------------------------------------
$SaUpdate  = Join-Path $SaRoot 'sa-update.exe'
$LogDir    = Join-Path $SaRoot 'logs'
$UpdateLog = Join-Path $LogDir 'sa-update.log'

# --- Helper: timestamped log (console + file) --------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts][$Level] $Message"
    $colors = @{ INFO = 'Cyan'; WARN = 'Yellow'; ERROR = 'Red' }
    Write-Host $line -ForegroundColor ($colors[$Level] ?? 'White')
    Add-Content -Path $UpdateLog -Value $line
}

# === PREFLIGHT ================================================================

if (-not (Test-Path -LiteralPath $SaUpdate)) {
    throw "sa-update.exe not found at: ${SaUpdate}`nVerify `$SaRoot is correct."
}
if (-not (Test-Path -LiteralPath $StartScript)) {
    throw "start-spamd.ps1 not found at: ${StartScript}`nVerify `$StartScript path."
}

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# === RUN SA-UPDATE ============================================================

$saArgs = @()
if ($NoGpg) {
    $saArgs += '--no-gpg'
    Write-Log 'GPG verification disabled (--no-gpg). Install Gpg4win for full security.' 'WARN'
}

Write-Log "Running sa-update $($saArgs -join ' ')"

# Merge stdout + stderr into the update log while also displaying on console
& $SaUpdate @saArgs 2>&1 | Tee-Object -FilePath $UpdateLog -Append

# sa-update exit codes:
#   0 = updates were downloaded and applied
#   1 = no updates available (rules are already current) -- NOT an error
#   >1 = actual failure (network, GPG, etc.)
$exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
Write-Log "sa-update finished with exit code: ${exitCode}"

# === HANDLE EXIT CODE =========================================================

switch ($exitCode) {
    0 {
        Write-Log 'Rules updated successfully. Restarting spamd to apply new rules...'
        Get-Process -Name 'spamd' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2

        & $StartScript 2>&1 | Tee-Object -FilePath $UpdateLog -Append
        Write-Log 'spamd restarted with updated rules.'
    }
    1 {
        # This is normal: sa-update returns 1 when rules are already current
        Write-Log 'Rules are already up to date (exit code 1). No restart needed.'
    }
    default {
        throw "sa-update failed with exit code ${exitCode}. Review log: ${UpdateLog}"
    }
}
