# ==============================================================================
# Author  : Mikhail Deynekin <mid1977@gmail.com> | https://deynekin.com
# GitHub  : https://github.com/paulmann
# Project : SpamAssassin for Windows — PowerShell 7 Automation Suite
# File    : start-spamd.ps1
# Purpose : Start Apache SpamAssassin spamd.exe as a background process
#           on Windows 11 / Windows Server without --daemonize
#           (POSIX::setsid is not available on Windows).
# Usage   : Called by Windows Task Scheduler at system startup,
#           or manually: .\start-spamd.ps1 [-DebugMode]
# ==============================================================================

[CmdletBinding()]
param(
    # Full path to the SpamAssassin installation directory.
    # Change this if you installed SpamAssassin to a different location.
    [string]$SaRoot = 'C:\mail\SpamAssasin',

    # IP address spamd will listen on.
    # Use 127.0.0.1 to accept connections from localhost only (recommended).
    # Use 0.0.0.0 to accept from all interfaces (only if spamd is firewalled).
    [string]$ListenIp = '127.0.0.1',

    # TCP port spamd listens on. Default is 783 (IANA registered for spamd).
    # Update hMailServer / WinSpamC / spamc settings if you change this.
    [int]$Port = 783,

    # Comma-separated list of IP addresses or CIDR blocks allowed to connect.
    # Default: localhost only. Add mail server IP if running on a separate host.
    [string]$AllowedIps = '127.0.0.1',

    # Maximum number of child processes spamd may spawn concurrently.
    # Increase on busy mail servers; decrease on low-RAM machines.
    [int]$MaxChildren = 5,

    # Enable verbose SpamAssassin debug output in the stdout log.
    # Useful for diagnosing rule loading, Bayes, DNS, or plugin issues.
    [switch]$DebugMode
)

$ErrorActionPreference = 'Stop'

# --- Derived paths (do not edit unless you know what you are doing) -----------
$SpamdPath = Join-Path $SaRoot 'spamd.exe'
$LogDir    = Join-Path $SaRoot 'logs'
$StdOutLog = Join-Path $LogDir 'spamd-stdout.log'
$StdErrLog = Join-Path $LogDir 'spamd-stderr.log'
$PidFile   = Join-Path $LogDir 'spamd.pid'

# --- Helper: timestamped console output --------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $colors = @{ INFO = 'Cyan'; WARN = 'Yellow'; ERROR = 'Red' }
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $colors[$Level]
}

# --- Helper: non-throwing TCP port probe -------------------------------------
function Test-TcpPort {
    param([string]$ComputerName, [int]$PortNum)
    try {
        return [bool](Test-NetConnection -ComputerName $ComputerName -Port $PortNum `
            -InformationLevel Quiet -WarningAction SilentlyContinue)
    } catch {
        return $false
    }
}

# === PREFLIGHT ================================================================

if (-not (Test-Path -LiteralPath $SpamdPath)) {
    throw "spamd.exe not found at: $SpamdPath`nVerify `$SaRoot is correct."
}

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# Kill any existing spamd instance to avoid port conflicts
$existing = Get-Process -Name 'spamd' -ErrorAction SilentlyContinue
if ($existing) {
    $ids = ($existing | Select-Object -ExpandProperty Id) -join ', '
    Write-Log "Found existing spamd process(es) [PID: ${ids}]. Terminating..." 'WARN'
    $existing | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# Verify the target port is not occupied by another process
if (Test-TcpPort -ComputerName $ListenIp -PortNum $Port) {
    throw "Port ${Port} on ${ListenIp} is already in use by another process.`nResolve the conflict before starting spamd."
}

# === BUILD ARGUMENT LIST ======================================================

$arguments = @(
    "--listen-ip=${ListenIp}",
    "--port=${Port}",
    "--allowed-ips=${AllowedIps}",
    "--max-children=${MaxChildren}"
)

if ($DebugMode) { $arguments += '--debug' }

Write-Log "Starting: $SpamdPath $($arguments -join ' ')"

# === LAUNCH ===================================================================

$proc = Start-Process `
    -FilePath         $SpamdPath `
    -ArgumentList     $arguments `
    -WorkingDirectory $SaRoot `
    -WindowStyle      Hidden `
    -RedirectStandardOutput $StdOutLog `
    -RedirectStandardError  $StdErrLog `
    -PassThru

# Persist PID for monitoring and update scripts
$proc.Id | Set-Content -Path $PidFile -Encoding ascii

# === POST-LAUNCH HEALTH CHECK =================================================

Write-Log 'Waiting 3 seconds for spamd to initialize...'
Start-Sleep -Seconds 3

if ($proc.HasExited) {
    $stderrContent = if (Test-Path $StdErrLog) { Get-Content $StdErrLog -Raw } else { '(no stderr captured)' }
    throw "spamd exited immediately after launch. ExitCode=$($proc.ExitCode)`n${stderrContent}"
}

$pid_  = $proc.Id
$alive = Test-TcpPort -ComputerName $ListenIp -PortNum $Port

if ($alive) {
    Write-Log "spamd is running. PID=${pid_} | Listening on ${ListenIp}:${Port}"
    Write-Log "stdout log : ${StdOutLog}"
    Write-Log "stderr log : ${StdErrLog}"
} else {
    Write-Log "Process launched (PID=${pid_}) but port ${Port} is not yet responding. Check ${StdErrLog} for details." 'WARN'
}
