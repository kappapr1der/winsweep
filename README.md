# WinSweep

WinSweep is a Windows cleanup toolkit for cache-heavy machines: Spotify,
Telegram, browsers, game launchers, GPU shader caches, Windows temp folders,
developer caches, safe recent-history registry cleanup, and scheduled pressure
guards.

The default rule is simple: clean disposable cache and temp data, not personal
files. WinSweep does not touch Downloads, Desktop, Documents, photos, videos,
projects, browser passwords, cookies, game saves, or whole application folders.

## Quick Start

Run this once as administrator:

```bat
setup-desktop-folder.bat
```

It creates:

```text
Desktop\WinSweep
```

Then start:

```bat
winsweep-menu.bat
```

## Menu

`winsweep-menu.bat` is the easiest entry point:

- Scan results: broad scan, no deletion, opens an HTML report.
- Safe cleanup: normal safe cache cleanup.
- Gaming cleanup: game launchers, browser/app caches, GPU shader caches.
- Deep cleanup: administrator cleanup with Windows component cleanup.
- Emergency cleanup: more aggressive safe cleanup for low disk space.
- Disk analyzer lite: top large folders on fixed drives, no deletion.
- Cleanup history: recent WinSweep runs and reclaimed size.
- Open latest HTML report.
- Install scheduled tasks.
- Edit config.
- Build release zip.

## Profiles

PowerShell examples:

```powershell
.\cleanup-windows.ps1 -Analyze -Profile Emergency -OpenReport
.\cleanup-windows.ps1 -Profile Safe -OpenReport
.\cleanup-windows.ps1 -Profile Gaming -OpenReport
.\cleanup-windows.ps1 -Profile Deep
```

Profiles:

- `Safe`: safe temp, browser, app, Spotify, game, and graphics caches.
- `Gaming`: game launchers plus short-age app/browser/GPU cache cleanup.
- `Deep`: safe cleanup plus developer caches, registry MRU cleanup, DISM.
- `Emergency`: deep safe cleanup with zero-day temp/cache age thresholds.

## Config

WinSweep reads `winsweep-config.json` from the same folder as
`cleanup-windows.ps1`.

Command-line flags win over config values. This keeps old `.bat` launchers and
scheduled tasks predictable.

Useful settings:

- `defaultProfile`
- `thresholds.minFreeGB`
- `thresholds.minFreePercent`
- `thresholds.tempOlderThanDays`
- `thresholds.cacheOlderThanDays`
- `features.developerCaches`
- `features.gameCaches`
- `features.clearRecycleBin`
- `schedule.guardEveryHours`
- `schedule.deepWeekly`

See `CONFIG.md` for the compact field guide.

## Scheduled Tasks

Run as administrator:

```bat
install-scheduled-cleanup.bat
```

The installer creates tasks under:

```text
Task Scheduler Library\Codex Windows Cleanup
```

Tasks:

- `Pressure Guard`: checks disk pressure every few hours and cleans only when
  free space is below the configured threshold.
- `Startup Guard`: checks shortly after logon.
- `Deep Weekly`: weekly deeper cleanup.

Default thresholds:

```text
below 35 GB free OR below 18% free
```

## HTML Reports

Manual scan/cleanup launchers can create an HTML report under:

```text
C:\ProgramData\CodexWindowsCleanup\Logs\Reports
```

If ProgramData is unavailable, WinSweep falls back to:

```text
%TEMP%\CodexWindowsCleanup\Logs\Reports
```

Open the latest report with:

```bat
open-latest-report.bat
```

Reports include summary metrics, top cleanup targets, preflight warnings,
retry tips, and all scanned targets.

## Preflight

Before cleanup, WinSweep checks whether common cache-heavy apps are open:

- Spotify
- Telegram Desktop
- Discord
- Slack
- Teams
- browsers
- Steam
- Epic Games Launcher
- Battle.net
- Riot Client
- Ubisoft Connect
- Rockstar Launcher

It does not kill processes. It only warns you when closing an app could free
more cache files.

## Disk Analyzer Lite

Run:

```bat
disk-analyzer-lite.bat
```

It scans fixed drives and shows the largest top-level folders and user
hotspots. It never deletes files.

## Release Zip

Run:

```bat
build-release.bat
```

It creates:

```text
dist\WinSweep-vX.Y.Z.zip
```

## GitHub Releases

The repository includes `.github/workflows/release.yml`.

Automatic release by tag:

```bash
git tag v0.4.2
git push origin v0.4.2
```

GitHub Actions will build `dist\WinSweep-v0.4.2.zip` and publish it on the
GitHub Releases page.

Manual release:

1. Open the repository on GitHub.
2. Go to `Actions`.
3. Select `Release`.
4. Click `Run workflow`.
5. Enter a version such as `0.4.2`.

The workflow uses the built-in `GITHUB_TOKEN` with `contents: write`.

## Safety Notes

WinSweep intentionally avoids:

- Downloads, Desktop, Documents, photos, videos, projects.
- Browser passwords, cookies, sessions.
- Whole application folders.
- Game saves.
- Manual deletion inside `WinSxS`.
- COM, drivers, uninstall records, file associations.
- Recycle Bin unless `-ClearRecycleBin` or config enables it.

Registry cleanup is limited to MRU/recent-history style keys and creates `.reg`
backups before deletion.
