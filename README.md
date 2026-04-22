# SpamAssassin for Windows Automation Suite

A production-oriented PowerShell 7 toolkit for running **Apache SpamAssassin on Windows 11 Pro / Windows Server** with clean process control, startup automation, scheduled rules updates, structured logging, and an operational workflow suitable for real-world mail environments.

![Platform](https://img.shields.io/badge/Platform-Windows%2011%20%7C%20Server%202016%2B-lightgrey)
![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)
![SpamAssassin](https://img.shields.io/badge/SpamAssassin-4.x-orange)
![Task Scheduler](https://img.shields.io/badge/Scheduler-Windows%20Task%20Scheduler-0078D4)
![License](https://img.shields.io/badge/License-MIT-yellow)

This repository provides a **Windows-native operational wrapper** around the JAM Software port of SpamAssassin. It solves the practical issues that typically appear when deploying SpamAssassin on Windows: background execution, safe restart behavior, logging, scheduled startup, and repeatable `sa-update` automation.

Unlike ad hoc examples, this toolkit is designed with a **systems-administration mindset**: explicit paths, defensive checks, clean task registration, reproducible startup behavior, and readable logs.

---

## Table of Contents

1. [Overview](#overview)
2. [Key Features](#key-features)
3. [Architecture](#architecture)
4. [Repository Layout](#repository-layout)
5. [Requirements](#requirements)
6. [Installation](#installation)
   - 6.1 [Install SpamAssassin for Windows](#61-install-spamassassin-for-windows)
   - 6.2 [Optional: Install Gpg4win](#62-optional-install-gpg4win)
   - 6.3 [Prepare the Directory Structure](#63-prepare-the-directory-structure)
   - 6.4 [Copy the Scripts](#64-copy-the-scripts)
7. [Configuration](#configuration)
   - 7.1 [Folder Paths](#71-folder-paths)
   - 7.2 [Listener and Port Settings](#72-listener-and-port-settings)
   - 7.3 [PATH Integration](#73-path-integration)
8. [Scripts](#scripts)
   - 8.1 [`start-spamd.ps1`](#81-start-spamdps1)
   - 8.2 [`update-spamassassin.ps1`](#82-update-spamassassinps1)
   - 8.3 [`create-spamassassin-tasks.ps1`](#83-create-spamassassin-tasksps1)
9. [Usage](#usage)
   - 9.1 [Manual Startup Test](#91-manual-startup-test)
   - 9.2 [Manual Rules Update](#92-manual-rules-update)
   - 9.3 [Register Scheduled Tasks](#93-register-scheduled-tasks)
   - 9.4 [Run Tasks Manually](#94-run-tasks-manually)
10. [Task Scheduler Design](#task-scheduler-design)
11. [Logging](#logging)
12. [Operational Workflow](#operational-workflow)
13. [hMailServer Integration Notes](#hmailserver-integration-notes)
14. [Troubleshooting](#troubleshooting)
15. [Security Considerations](#security-considerations)
16. [Recommended Production Practices](#recommended-production-practices)
17. [FAQ](#faq)
18. [Author](#author)
19. [License](#license)

---

## Overview

**SpamAssassin for Windows Automation Suite** is a compact but production-minded PowerShell 7 deployment layer for the Windows port of SpamAssassin.

Its purpose is straightforward:

- start `spamd.exe` reliably on Windows without unsupported Unix daemonization semantics;
- keep all runtime artifacts in predictable locations;
- update rules on a schedule using `sa-update.exe`;
- restart the filtering daemon only when appropriate;
- expose a clean maintenance workflow for future mail-server integration.

This project intentionally avoids fragile “launch it once and hope it stays up” patterns. Instead, it implements explicit checks for executable presence, process conflicts, busy ports, task registration, and runtime logging.

---

## Key Features

- **Windows-safe process startup** without `--daemonize`.
- **PowerShell 7-first implementation** with clean parameterized scripts.
- **Separation of concerns**: one script for startup, one for updates, one for scheduler registration.
- **Structured logging** for startup, stderr, stdout, and rule updates.
- **Graceful service-like behavior** using Windows Task Scheduler instead of Unix assumptions.
- **Defensive preflight checks** for missing binaries, stale processes, and occupied ports.
- **SYSTEM-level scheduled tasks** with elevated privileges for reliable execution at boot.
- **Optional GPG validation path** via Gpg4win for `sa-update` signature verification.
- **Operational readiness for hMailServer** or similar Windows mail routing workflows.

---

## Architecture

The toolkit is based on a simple operational model:

1. `start-spamd.ps1` launches `spamd.exe` in a Windows-compatible way.
2. `update-spamassassin.ps1` runs `sa-update.exe`, records output, and restarts `spamd` only when updates are actually applied.
3. `create-spamassassin-tasks.ps1` registers two Windows Scheduled Tasks:
   - one at system startup for daemon launch;
   - one daily task for rules maintenance.

This approach is preferable on Windows because native SpamAssassin daemonization flags rely on POSIX behavior that is **not implemented on Windows**. Using Task Scheduler plus PowerShell yields deterministic startup behavior without forcing Unix semantics onto the platform.

---

## Repository Layout

```text
C:\mail\
├── SpamAssasin\
│   ├── spamd.exe
│   ├── sa-update.exe
│   ├── spamassassin.exe
│   ├── WinSpamC.exe
│   └── logs\
│       ├── spamd-stdout.log
│       ├── spamd-stderr.log
│       ├── spamd.pid
│       └── sa-update.log
│
└── scripts\
    └── spam\
        ├── start-spamd.ps1
        ├── update-spamassassin.ps1
        ├── create-spamassassin-tasks.ps1
        └── README.md
```

---

## Requirements

| Component | Recommended Version | Notes |
|---|---:|---|
| Windows | 11 Pro / Server 2022+ | Windows 10 / Server 2016+ also acceptable |
| PowerShell | 7.x | Required for consistent script behavior |
| SpamAssassin for Windows | 4.x | JAM Software build |
| Gpg4win | Current stable | Optional but strongly recommended |
| Privileges | Administrator | Required for PATH and task registration |

---

## Installation

### 6.1 Install SpamAssassin for Windows

Install the JAM Software Windows build of SpamAssassin into the following directory:

```text
C:\mail\SpamAssasin
```

After installation, verify that the expected binaries exist:

```powershell
Get-ChildItem 'C:\mail\SpamAssasin'
```

At minimum, confirm the presence of:

```text
spamd.exe
sa-update.exe
spamassassin.exe
WinSpamC.exe
```

Validate the installed version:

```powershell
cd 'C:\mail\SpamAssasin'
.\spamassassin.exe -V
```

### 6.2 Optional: Install Gpg4win

If you want `sa-update.exe` to validate signed rules properly, install Gpg4win.

Using `winget`:

```powershell
winget install -e --id GnuPG.Gpg4win
```

After installation, verify:

```powershell
gpg --version
```

If GPG is not installed, the update script can still operate with `--no-gpg`, but that should be considered a compromise rather than a best practice.

### 6.3 Prepare the Directory Structure

Create the scripts directory if it does not yet exist:

```powershell
New-Item -ItemType Directory -Path 'C:\mail\scripts\spam' -Force
```

### 6.4 Copy the Scripts

Place the following files into:

```text
C:\mail\scripts\spam\
```

- `start-spamd.ps1`
- `update-spamassassin.ps1`
- `create-spamassassin-tasks.ps1`
- `README.md`

---

## Configuration

### 7.1 Folder Paths

The default installation path used throughout the scripts is:

```text
C:\mail\SpamAssasin
```

If your installation differs, update the following parameters or defaults accordingly:

- `-SaRoot`
- `-StartScript`
- `-ScriptsRoot`

### 7.2 Listener and Port Settings

The recommended local-only startup configuration is:

```text
127.0.0.1:783
```

This keeps `spamd` available only to local processes such as hMailServer, helper scripts, or `WinSpamC.exe` while preventing unnecessary network exposure.

### 7.3 PATH Integration

If you want to invoke SpamAssassin executables from any terminal session, add the installation directory to the machine PATH.

```powershell
$saPath = 'C:\mail\SpamAssasin'
$old = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$parts = $old -split ';' | Where-Object { $_ -and ($_ -ne $saPath) } | Select-Object -Unique
$parts += $saPath
[Environment]::SetEnvironmentVariable('Path', ($parts -join ';').TrimEnd(';'), 'Machine')
```

Open a fresh PowerShell session and verify:

```powershell
spamassassin.exe -V
```

---

## Scripts

## 8.1 `start-spamd.ps1`

This is the operational entry point for starting the daemon.

### Responsibilities

- verifies that `spamd.exe` exists;
- creates the log directory if needed;
- kills stale `spamd` processes if they already exist;
- checks whether the configured TCP port is already occupied;
- starts the process hidden in the background;
- writes the process ID to a PID file;
- verifies post-start port reachability.

### Default invocation behavior

```powershell
.\start-spamd.ps1
```

### Example with explicit parameters

```powershell
.\start-spamd.ps1 `
  -SaRoot 'C:\mail\SpamAssasin' `
  -ListenIp '127.0.0.1' `
  -Port 783 `
  -AllowedIps '127.0.0.1' `
  -MaxChildren 5
```

### Example with debug mode

```powershell
.\start-spamd.ps1 -DebugMode
```

### Why there is no `--daemonize`

On Windows, SpamAssassin should **not** be started with `--daemonize`. That flag relies on POSIX session semantics and leads to failures such as:

```text
POSIX::setsid not implemented on this architecture
```

This project deliberately uses Windows process management rather than attempting to emulate Unix daemonization.

---

## 8.2 `update-spamassassin.ps1`

This script performs rule maintenance.

### Responsibilities

- runs `sa-update.exe`;
- records all output to `sa-update.log`;
- interprets update exit codes;
- restarts `spamd` only if new rules were actually applied;
- supports an optional `-NoGpg` switch.

### Standard usage

```powershell
.\update-spamassassin.ps1
```

### Usage without GPG verification

```powershell
.\update-spamassassin.ps1 -NoGpg
```

### Exit code handling

| Exit Code | Meaning | Script Behavior |
|---|---|---|
| `0` | Updates installed | Restart `spamd` |
| `1` | No updates available | Log informational result and exit cleanly |
| Other | Error | Throw exception and preserve logs |

This behavior prevents unnecessary daemon restarts and keeps routine maintenance quiet when rules are already current.

---

## 8.3 `create-spamassassin-tasks.ps1`

This script registers the Windows Scheduled Tasks used by the toolkit.

### Responsibilities

- validates that `pwsh.exe`, `start-spamd.ps1`, and `update-spamassassin.ps1` exist;
- creates a dedicated `\SpamAssassin` task folder if needed;
- registers a startup task running as `SYSTEM`;
- registers a daily update task running as `SYSTEM`;
- applies sane scheduler settings such as `Highest` run level and `IgnoreNew` for multiple instances.

### Standard usage

```powershell
cd 'C:\mail\scripts\spam'
.\create-spamassassin-tasks.ps1
```

### Example with custom update time

```powershell
.\create-spamassassin-tasks.ps1 -UpdateTime '02:15'
```

---

## Usage

## 9.1 Manual Startup Test

Before involving Task Scheduler, always validate startup manually:

```powershell
cd 'C:\mail\scripts\spam'
.\start-spamd.ps1
```

Then confirm the port is reachable:

```powershell
Test-NetConnection 127.0.0.1 -Port 783
```

And confirm the process exists:

```powershell
Get-Process -Name spamd -ErrorAction SilentlyContinue
```

## 9.2 Manual Rules Update

Run a one-time rules update before enabling scheduled maintenance:

```powershell
cd 'C:\mail\scripts\spam'
.\update-spamassassin.ps1
```

If GPG is not yet available:

```powershell
.\update-spamassassin.ps1 -NoGpg
```

## 9.3 Register Scheduled Tasks

Register both tasks from an elevated PowerShell 7 session:

```powershell
cd 'C:\mail\scripts\spam'
.\create-spamassassin-tasks.ps1
```

## 9.4 Run Tasks Manually

After registration, you can invoke them directly:

```powershell
Start-ScheduledTask -TaskPath '\SpamAssassin' -TaskName 'SpamAssassin-spamd-Startup'
Start-ScheduledTask -TaskPath '\SpamAssassin' -TaskName 'SpamAssassin-Update-Daily'
```

Check task states:

```powershell
Get-ScheduledTask -TaskPath '\SpamAssassin' | Format-Table TaskName, State
```

---

## Task Scheduler Design

The scheduler layer is intentionally conservative.

### Startup task

- **Task Name:** `SpamAssassin-spamd-Startup`
- **Trigger:** At system startup
- **Account:** `SYSTEM`
- **Run Level:** Highest
- **Purpose:** ensure the daemon is available immediately after boot

### Update task

- **Task Name:** `SpamAssassin-Update-Daily`
- **Trigger:** Daily (default `03:30`)
- **Account:** `SYSTEM`
- **Run Level:** Highest
- **Purpose:** refresh SpamAssassin rules and restart the daemon only when new rules are applied

### Why Task Scheduler instead of Startup Folder or Run keys?

Because Task Scheduler provides:

- execution before user logon;
- a stable SYSTEM security context;
- retry and timeout semantics;
- a central administrative UI;
- a cleaner operational story for infrastructure systems.

For infrastructure-grade Windows automation, Task Scheduler is the correct primitive.

---

## Logging

All runtime logs are written beneath:

```text
C:\mail\SpamAssasin\logs\
```

### Files

| File | Purpose |
|---|---|
| `spamd-stdout.log` | Standard output from `spamd.exe` |
| `spamd-stderr.log` | Error output from `spamd.exe` |
| `spamd.pid` | Last launched process ID |
| `sa-update.log` | Rules update execution log |

### Example log inspection

```powershell
Get-Content 'C:\mail\SpamAssasin\logs\spamd-stderr.log' -Tail 50
Get-Content 'C:\mail\SpamAssasin\logs\sa-update.log' -Tail 100
```

The log model is intentionally split rather than multiplexed into a single file because separate stdout/stderr streams make root-cause analysis substantially easier.

---

## Operational Workflow

A clean deployment sequence looks like this:

1. Install SpamAssassin into `C:\mail\SpamAssasin`.
2. Optionally install Gpg4win.
3. Copy the PowerShell scripts into `C:\mail\scripts\spam`.
4. Run `start-spamd.ps1` manually and validate port 783.
5. Run `update-spamassassin.ps1` manually and inspect `sa-update.log`.
6. Register the scheduled tasks.
7. Reboot the machine and confirm automatic startup.
8. Integrate the running daemon with the mail pipeline.

For production, treat steps 4 and 5 as mandatory validation, not optional convenience.

---

## hMailServer Integration Notes

This toolkit does **not** directly modify hMailServer configuration, but it is built to support a local integration model.

### Typical local daemon target

```text
Host: 127.0.0.1
Port: 783
```

### If using `WinSpamC.exe`

A common invocation pattern is:

```text
-s 512000 -d 127.0.0.1 -p 783
```

### Example administrative intent

- keep `spamd` local-only;
- let hMailServer or another local mail pipeline submit messages for scoring;
- consume `X-Spam-*` headers and SpamAssassin score output for delivery logic.

This is the cleanest Windows deployment model unless there is a specific reason to expose the daemon beyond localhost.

---

## Troubleshooting

### `POSIX::setsid not implemented on this architecture`

**Cause:** `spamd.exe` was started with `--daemonize` on Windows.

**Fix:** remove `--daemonize` entirely and use the provided launcher.

```powershell
.\start-spamd.ps1
```

### `Variable reference is not valid. ':' was not followed by a valid variable name character`

**Cause:** PowerShell string interpolation used a construct such as:

```powershell
"$ListenIp:$Port"
```

**Fix:** use explicit variable delimiters:

```powershell
"${ListenIp}:${Port}"
```

### `gpg required but not found`

**Cause:** `sa-update.exe` expects `gpg.exe` for signature verification.

**Fix option 1:** install Gpg4win.

```powershell
winget install -e --id GnuPG.Gpg4win
```

**Fix option 2:** use `-NoGpg`.

```powershell
.\update-spamassassin.ps1 -NoGpg
```

### Port 783 is already in use

Identify the owning process:

```powershell
netstat -ano | findstr :783
```

Terminate it if appropriate:

```powershell
Stop-Process -Id <PID> -Force
```

### Startup task exists but spamd is not running

Check task status:

```powershell
Get-ScheduledTask -TaskPath '\SpamAssassin' | Format-Table TaskName, State
```

Check last run results in Task Scheduler UI and inspect:

```powershell
Get-Content 'C:\mail\SpamAssasin\logs\spamd-stderr.log' -Tail 100
```

### `sa-update` logs exist but rules do not seem to apply

That usually indicates one of the following:

- no update was available (`exit code 1`);
- the update ran successfully but the daemon restart failed;
- GPG validation failed and the run aborted.

Inspect:

```powershell
Get-Content 'C:\mail\SpamAssasin\logs\sa-update.log' -Tail 200
```

---

## Security Considerations

This toolkit intentionally favors a conservative security posture.

- **Bind to localhost only** unless remote access is explicitly required.
- **Run scheduled tasks as SYSTEM** only because this is the most reliable startup context for infrastructure automation on Windows.
- **Restrict write permissions** on `C:\mail\SpamAssasin` and `C:\mail\scripts\spam`.
- **Prefer GPG verification** whenever possible.
- **Avoid exposing port 783 externally** unless protected by firewall policy and justified by architecture.
- **Treat logs as operational data** because they may reveal mail-processing behavior or environment details.

If this deployment ever moves from a standalone mail lab to a public-facing server, revisit file ACLs, Windows Defender exclusions, backup policy, and your local firewall rules.

---

## Recommended Production Practices

For a cleaner long-term deployment, the following practices are recommended:

- keep all mail-filtering assets under `C:\mail\` or a similarly explicit operational root;
- back up your scripts before changing scheduler logic;
- monitor the `spamd.pid` file and port 783 as part of your health checks;
- archive or rotate `sa-update.log` if long retention is expected;
- test rule updates manually before major mailflow changes;
- document your hMailServer integration arguments in the same repository;
- keep PowerShell 7 updated independently from Windows PowerShell 5.1.

If you want a stricter production model, the next natural improvements are:

- log rotation;
- health-check and auto-remediation task;
- optional Windows Event Log integration;
- dedicated repository tags for release snapshots;
- CI linting for PowerShell formatting and syntax.

---

## FAQ

### Is this a native Windows service implementation?

Not in the SCM sense. It is a **service-like operational model** built on Task Scheduler, which is generally the cleanest no-wrapper option for this toolchain on Windows.

### Why not use NSSM, AlwaysUp, or FireDaemon?

Those products are valid options, but this repository intentionally keeps the stack minimal and built on native Windows capabilities plus PowerShell 7.

### Can this be used with hMailServer?

Yes. That is one of the primary deployment targets for a localhost-bound `spamd` instance.

### Is `-NoGpg` acceptable in production?

Only if you understand the trade-off. It removes signature verification and should be treated as a fallback path, not the preferred design.

### Why is the directory spelled `SpamAssasin` instead of `SpamAssassin`?

Because the scripts were built around the current local deployment path. If you want the canonical spelling, rename the directory and update the script defaults consistently.

---

## Author

**Mikhail Deynekin**  
Senior Infrastructure Engineer / Developer  
AI enthusiast, systems administrator, and automation-focused full-stack engineer

- Website: [deynekin.com](https://deynekin.com)
- Email: [mid1977@gmail.com](mailto:mid1977@gmail.com)

If you are publishing this project on GitHub, the recommended repository description would be:

```text
Production-oriented PowerShell 7 automation toolkit for running SpamAssassin on Windows with startup tasks, scheduled rule updates, logging, and hMailServer-ready local integration.
```

Recommended topics:

```text
spamassassin windows powershell powershell7 task-scheduler hmailserver antispam mailserver automation
```

---

## License

This repository may be released under the MIT License.

SpamAssassin itself is an Apache Software Foundation project. Review the upstream project and the JAM Software Windows port licensing terms before redistributing binaries.

---

## Final Notes

This README is intentionally written as an **operations-grade GitHub document**, not just a quickstart note. The goal is to give the next administrator enough clarity to understand how the system starts, how it updates, how it fails, and how to maintain it without reverse-engineering the scripts.

If you want, the next logical step is a second pass that upgrades this repository into a **fully polished GitHub release package** with:

- a refined repository title and subtitle;
- a changelog;
- versioned release notes;
- a `.gitignore` tuned for PowerShell and Windows;
- a `LICENSE` file;
- badges for release/version/build status;
- a dedicated `docs/` section for hMailServer integration.
