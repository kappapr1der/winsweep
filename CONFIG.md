# WinSweep config

WinSweep reads `winsweep-config.json` from the same folder as
`cleanup-windows.ps1`. Command-line flags always win over config values.

Useful fields:

- `defaultProfile`: `Safe`, `Gaming`, `Deep`, `Emergency`, or empty string.
- `thresholds.minFreeGB`: pressure guard starts cleanup below this many GB.
- `thresholds.minFreePercent`: pressure guard starts cleanup below this percent.
- `thresholds.tempOlderThanDays`: age cutoff for temp files.
- `thresholds.cacheOlderThanDays`: age cutoff for cache files.
- `paths.extraPathsFile`: usually `extra-cache-paths.txt`.
- `paths.logDir`: leave empty for the automatic ProgramData/TEMP log folder.
- `features.registry`: enables safe MRU/recent-history registry cleanup.
- `features.developerCaches`: enables npm/pip/NuGet/Gradle cache cleanup.
- `features.clearRecycleBin`: disabled by default.
- `schedule.guardStart`: first daily pressure-guard check, for example `00:15`.
- `schedule.guardEveryHours`: pressure-guard check interval.
- `schedule.deepWeekly`: weekly deep-clean time, for example `03:20`.
- `schedule.deepDay`: weekday for deep cleanup.

Run `winsweep-menu.bat` for the easiest local workflow.
