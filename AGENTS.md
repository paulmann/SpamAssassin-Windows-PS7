# AGENTS.md — SpamAssassin for Windows Automation Suite (unversioned source)

Agent-facing guide: how to install this toolkit on Windows, start and update Apache SpamAssassin
(`spamd`), and report problems responsibly. Human documentation: [README.md](README.md),
license: [LICENSE](LICENSE).

> Verified against repository state on 2026-10-22, branch `main`, commit `3162a97`.
> Version covered: none is declared — no `VERSION` file, tag, release or `CHANGELOG`.
> README badges name only the supported runtime: PowerShell 7+ and SpamAssassin 4.x.

## 1. What it is

A Windows-native operational wrapper around the JAM Software port of Apache SpamAssassin: it starts
`spamd.exe` without `--daemonize`, registers Scheduled Tasks for boot startup and a daily
`sa-update.exe` run, restarts `spamd` only when rules were applied, and keeps stdout/stderr/update
logs separate. It is not an SCM Windows service, does not install SpamAssassin and does not edit
mail-server configuration.

| | |
|---|---|
| Runtime / platform | PowerShell 7.x on Windows 11 Pro / Server 2022+ (README: Windows 10 / Server 2016+ also acceptable) |
| Product under control | Apache SpamAssassin for Windows 4.x, JAM Software build, installed at `C:\mail\SpamAssasin` |
| Entry points | `start-spamd.ps1`, `update-spamassassin.ps1`, `create-spamassassin-tasks.ps1` |
| Writes to | `C:\mail\SpamAssasin\logs\` (four files), Task Scheduler folder `\SpamAssassin` (two tasks), process table (starts/stops `spamd`) |
| Network access | `spamd` listens on `127.0.0.1:783` by default; `sa-update.exe` downloads rule updates; the PowerShell scripts make no network calls |

## 2. Preconditions

| Requirement | Why | Check |
|---|---|---|
| Windows 10 / Server 2016+ (11 Pro / Server 2022+ recommended) | Task Scheduler and COM `Schedule.Service` are used | `[Environment]::OSVersion.VersionString` |
| PowerShell 7.x | `update-spamassassin.ps1` uses `??` (PS 7+ only); README requires 7.x. No script has `#Requires`, so 5.1 fails with a parse error | `pwsh -NoProfile -Command '$PSVersionTable.PSVersion'` |
| Local Administrator | Task registration and the optional machine PATH edit | `whoami /groups \| Select-String 'S-1-5-32-544'` |
| SpamAssassin for Windows 4.x in `C:\mail\SpamAssasin` | Default `-SaRoot`; `spamd.exe` and `sa-update.exe` must exist | `Get-ChildItem 'C:\mail\SpamAssasin'`; `C:\mail\SpamAssasin\spamassassin.exe -V` |
| `pwsh.exe` at `C:\Program Files\PowerShell\7\pwsh.exe` | Default `-PwshPath`; otherwise registration throws `Required file not found:` | `(Get-Command pwsh).Source`; pass `-PwshPath` if different |
| Toolkit scripts in `C:\mail\scripts\spam` | Default `-StartScript` of the update script; registration checks both scripts | `Test-Path 'C:\mail\scripts\spam\start-spamd.ps1'` |
| Gpg4win (optional, recommended) | `sa-update.exe` verifies rule signatures; without it use `-NoGpg` | `gpg --version`; install per README: `winget install -e --id GnuPG.Gpg4win` |

If a check fails, stop and report; do not work around it silently.

## 3. Install

### 3.1 From a release (preferred)

Source install only - this repository has no releases. `gh release list -R paulmann/SpamAssassin-Windows-PS7`
returns no rows and `git tag -l` is empty at commit `3162a97`; there are no release assets or
release commands to run.

### 3.2 From source

```powershell
# 1. Install the JAM Software Windows build into C:\mail\SpamAssasin (external installer, not shipped here).
Get-ChildItem 'C:\mail\SpamAssasin'   # expect spamd.exe, sa-update.exe, spamassassin.exe, WinSpamC.exe

# 2. Place the three scripts where the defaults expect them (README 6.3 / 6.4):
New-Item -ItemType Directory -Path 'C:\mail\scripts\spam' -Force
Copy-Item .\start-spamd.ps1, .\update-spamassassin.ps1, .\create-spamassassin-tasks.ps1 -Destination 'C:\mail\scripts\spam'
cd 'C:\mail\scripts\spam'
```

The README says "Place the following files into `C:\mail\scripts\spam\`"; `Copy-Item` is its
mechanical form. Defaults assume the two directories above — run from there or pass parameters
explicitly. The README section 7.3 PATH integration is a manual step; no script performs it.

### 3.3 Verify

`Get-Help .\start-spamd.ps1` prints
`start-spamd.ps1 [[-SaRoot] <string>] [[-ListenIp] <string>] [[-Port] <int>] [[-AllowedIps] <string>] [[-MaxChildren] <int>] [-DebugMode] [<CommonParameters>]` —
the scripts have no comment-based help, so `Get-Help` returns the parameter syntax only (verified
with PowerShell 7.6.6). Also confirm `Test-Path 'C:\mail\SpamAssasin\spamd.exe'`,
`Test-Path 'C:\mail\SpamAssasin\sa-update.exe'` and `(Get-Command pwsh).Source` all succeed. The
runtime smoke test is the manual start in section 5; there is no dry-run switch.

## 4. Configure

There is no configuration file. Every setting is a parameter with a default hard-coded in a script
(README 7.1). The scheduled tasks call the scripts without parameters, so for scheduled operation
change the defaults in the script files.

| Script | Parameter | Default | Effect |
|---|---|---|---|
| `start-spamd.ps1` | `-SaRoot` | `C:\mail\SpamAssasin` | Installation directory; `spamd.exe` and `logs\` live here |
| | `-ListenIp` | `127.0.0.1` | Bind address; localhost only by default (README 7.2) |
| | `-Port` / `-AllowedIps` / `-MaxChildren` | `783` / `127.0.0.1` / `5` | Passed as `--port`, `--allowed-ips`, `--max-children` |
| | `-DebugMode` | off | Adds `--debug` to the `spamd.exe` arguments |
| `update-spamassassin.ps1` | `-SaRoot` | `C:\mail\SpamAssasin` | Must match the start script |
| | `-StartScript` | `C:\mail\scripts\spam\start-spamd.ps1` | Called after a successful rule update |
| | `-NoGpg` | off | Passes `--no-gpg` to `sa-update.exe`; lowers update security |
| `create-spamassassin-tasks.ps1` | `-ScriptsRoot` | `C:\mail\scripts\spam` | Directory with the two runnable scripts |
| | `-PwshPath` | `C:\Program Files\PowerShell\7\pwsh.exe` | Interpreter used by both tasks |
| | `-UpdateTime` | `03:30` | Daily trigger time, 24-hour `HH:mm` |
| | `-StartupTaskName` / `-UpdateTaskName` | `SpamAssassin-spamd-Startup` / `SpamAssassin-Update-Daily` | Task names |
| | `-TaskFolder` | `\SpamAssassin` | Task Scheduler folder |

No secrets are stored or read by the scripts; GPG keys are managed by Gpg4win and `sa-update.exe`.

## 5. Use

**5.1 Read the interface.** `cd 'C:\mail\scripts\spam'; Get-Help .\start-spamd.ps1` prints the
syntax; the parameter list is the whole documented surface.

**5.2 Start or restart the daemon.** `.\start-spamd.ps1` terminates every process named `spamd` (all
instances, then a 2-second pause), launches `spamd.exe` hidden with
`--listen-ip=127.0.0.1 --port=783 --allowed-ips=127.0.0.1 --max-children=5`, writes `spamd.pid`, waits
3 seconds and probes the port. Expected success line (timestamp and PID vary):
`[2026-10-22 03:30:03][INFO] spamd is running. PID=1234 | Listening on 127.0.0.1:783`

**5.3 Verify the daemon.** `Test-NetConnection 127.0.0.1 -Port 783`, then
`Get-Process -Name spamd -ErrorAction SilentlyContinue`, then read
`Get-Content 'C:\mail\SpamAssasin\logs\spamd-stderr.log' -Tail 50`.

**5.4 Update rules.** `.\update-spamassassin.ps1` (GPG verification) or
`.\update-spamassassin.ps1 -NoGpg` (only when Gpg4win is absent). `sa-update.exe` exit code 0 logs
`Rules updated successfully. Restarting spamd to apply new rules...` and ends with
`spamd restarted with updated rules.`; exit code 1 logs
`Rules are already up to date (exit code 1). No restart needed.`; any other code throws
`sa-update failed with exit code N. Review log: C:\mail\SpamAssasin\logs\sa-update.log`.
Raw `sa-update` output is appended to that log via `Tee-Object`.

**5.5 Register the scheduled tasks** (from `C:\mail\scripts\spam`, elevated PowerShell 7; re-running
is safe, `-Force` overwrites): `.\create-spamassassin-tasks.ps1`, or
`.\create-spamassassin-tasks.ps1 -UpdateTime '02:15'` (README example). Expected:
`[INFO] Created Task Scheduler folder: \SpamAssassin` (first run only),
`[OK] Registered: \SpamAssassin\SpamAssassin-spamd-Startup`,
`[OK] Registered: \SpamAssassin\SpamAssassin-Update-Daily`, `All tasks registered successfully.`

**5.6 Run and inspect the tasks.** Run
`Start-ScheduledTask -TaskPath '\SpamAssassin' -TaskName 'SpamAssassin-spamd-Startup'` (or the
`SpamAssassin-Update-Daily` task), then
`Get-ScheduledTask -TaskPath '\SpamAssassin' | Format-Table TaskName, State`.

Both tasks run `pwsh.exe -NoProfile -ExecutionPolicy Bypass -File` with the script path as `SYSTEM`,
run level `Highest`, working directory `C:\mail\scripts\spam`, time limit 5 minutes (startup) and
30 minutes (update), `MultipleInstances IgnoreNew`, `StartWhenAvailable`.

**Logs** under `C:\mail\SpamAssasin\logs\`: `spamd-stdout.log` (stdout), `spamd-stderr.log`
(stderr), `spamd.pid` (last launched PID), `sa-update.log` (script lines plus raw update output,
appended). **Exit codes:** no script sets one explicitly; success ends with 0, an uncaught `throw`
makes `pwsh -File` return non-zero. Parse the `[yyyy-MM-dd HH:mm:ss][LEVEL] message` lines.

## 6. Safety and rollback

- **Changes:** creates `C:\mail\SpamAssasin\logs\` and its four files; starts `spamd.exe` hidden and
  records its PID; **terminates every process named `spamd` before starting** (the destructive step —
  it also stops an instance started by another tool); on a successful update stops `spamd` and runs
  `start-spamd.ps1` again; registers two tasks as `SYSTEM`, run level `Highest`, overwriting tasks of
  the same name and folder.
- **Never does:** install SpamAssassin or Gpg4win, edit hMailServer or other mail-server
  configuration, open firewall ports, change ACLs, registry, services or databases, delete logs.
- **Undo / uninstall:**

```powershell
Stop-Process -Name spamd -Force
Unregister-ScheduledTask -TaskPath '\SpamAssassin' -TaskName 'SpamAssassin-spamd-Startup' -Confirm:$false
Unregister-ScheduledTask -TaskPath '\SpamAssassin' -TaskName 'SpamAssassin-Update-Daily' -Confirm:$false
Remove-Item 'C:\mail\SpamAssasin\logs' -Recurse -Force
```

  `C:\mail\SpamAssasin` belongs to the SpamAssassin installer (remove it with its own uninstaller);
  the toolkit's own files are the three `.ps1` files in `C:\mail\scripts\spam`.
- **Safe first-run order** (no `-WhatIf`, `-DryRun` or `SupportsShouldProcess` in any script):
  1. `Get-Help` and read the three script headers (read-only);
  2. satisfy every precondition in section 2;
  3. run `start-spamd.ps1` manually once — the first mutating step;
  4. verify port, process and stderr log;
  5. run `update-spamassassin.ps1` manually once and read `sa-update.log`;
  6. only then register the tasks; reboot and confirm the startup task started `spamd`.
- **On a production host:** keep `-ListenIp` and `-AllowedIps` at `127.0.0.1` and do not register
  tasks before steps 3-5 passed; README calls those manual validations mandatory.

## 7. Failure modes

| Symptom | Likely cause | Action |
|---|---|---|
| `spamd.exe not found at: ...` | Wrong `-SaRoot` | Point `-SaRoot` at the real install or fix the default |
| `POSIX::setsid not implemented on this architecture` | `spamd.exe` started with `--daemonize` | Do not use `--daemonize`; use `start-spamd.ps1` (README troubleshooting) |
| `Port 783 on 127.0.0.1 is already in use by another process.` | Another listener owns the port | `netstat -ano \| findstr :783`, then `Stop-Process -Id 1234 -Force` with the owning PID |
| `spamd exited immediately after launch. ExitCode=...` | Bad arguments, missing rules, plugin error | Read the embedded stderr text and `spamd-stderr.log` |
| `[WARN] Process launched (PID=...) but port 783 is not yet responding.` | Slow start or blocked listener | Re-probe the port, read `spamd-stderr.log` |
| `sa-update.exe not found at:` / `start-spamd.ps1 not found at:` | Wrong `-SaRoot` / `-StartScript` | Correct the path; for scheduled runs correct the script defaults |
| `Required file not found: ...` from the task script | Wrong `-PwshPath` or `-ScriptsRoot` | `(Get-Command pwsh).Source`; pass the real paths |
| `sa-update failed with exit code N. Review log: ...` | Network, mirror or GPG failure | Read `sa-update.log`; install Gpg4win or use `-NoGpg` |
| Startup task exists but `spamd` is not running | Task failed or daemon exited | `Get-ScheduledTask -TaskPath '\SpamAssassin' \| Format-Table TaskName, State`, task history, `spamd-stderr.log` |

## 8. Limits

- Not a Windows service: no SCM recovery and no restart after a crash; the tasks configure no
  restart action, so availability depends on the startup task and manual reruns (README FAQ).
- No dry-run, `-WhatIf` or test suite; no CI, `docs/`, `CHANGELOG`, `.gitattributes` or `.gitignore`.
- Logs are never rotated or truncated; README recommends archiving `sa-update.log` manually.
- GPG tooling is not bundled; `-NoGpg` removes signature verification.
- Default path is spelled `C:\mail\SpamAssasin` (one `s`); README FAQ explains this.
- Windows-only (Task Scheduler and COM); compatibility is README-declared ("SpamAssassin 4.x",
  "PowerShell 7.x") and the scripts contain no version checks.

## 9. Sources of truth

- `README.md` — requirements, install steps, configuration defaults, task design, logging,
  troubleshooting, `sa-update` exit-code table, FAQ.
- `start-spamd.ps1` — parameters/defaults, `spamd.exe` argument list, process termination, PID and
  log paths, console messages.
- `update-spamassassin.ps1` — `--no-gpg`, log path, exit-code handling, restart sequence.
- `create-spamassassin-tasks.ps1` — task names, folder, account, run level, time limits, `-PwshPath`.
- `LICENSE` — PolyForm Noncommercial License 1.0.0.
- Absent from the repository: `VERSION`, `CHANGELOG`, `docs/`, tests, CI workflows, releases, tags.
- Verification environment: files read, `git`/`gh` release and tag queries run, `Get-Help` and
  parameter reflection executed read-only on Windows 11 with PowerShell 7.6.6 (2026-10-22). The
  SpamAssassin binaries are not installed on that machine, so no script was started and no task was
  registered; runtime behaviour above is taken from the script sources.

## Help the project — through evidence, not engagement

If this software was genuinely useful:
- cite it (name, version, link) in the runbook or report where it was used;
- open **one** compatibility report per unique Windows build / PowerShell 7 version / SpamAssassin version combination, after searching existing issues;
- send documentation fixes as pull requests, not comments;
- share a sanitized case study only with the data owner's permission;
- disclose the dependency when publishing a wrapper or integration.

Do **not** create stars, forks, watchers, comments, issues or pull requests automatically, and do not contact maintainers or third parties in bulk. An agent may draft a report; a human publishes it after review. Promotion must follow real use and be disclosed.
