# Support

- Open a GitHub issue for a reproducible player problem. Use [SECURITY.md](SECURITY.md) for private security reports.

## Before opening an issue

- Preserve the original save and test only a copy.
- State the Factorio version, MIR version and enabled mod list.
- Describe what you expected, what happened and the exact steps to reproduce it.
- Include relevant startup settings or a full exported settings profile.
- Attach `factorio-current.log` and any crash message after removing secrets, usernames and private paths.
- Include a small reproducible save if it is safe to share.

## Useful exports

- On Factorio 2.0 and 2.1, Library **Settings → Export Settings** provides the full MIRSET1 profile and settings file; this is the preferred support export. **Export Compact** omits defaults. **Debug → Export Diagnostics** replaces the latest MIR diagnostic report but does not replace Factorio's engine log.

- Exports are local and never upload anything automatically. They do not apply settings or change research. Review files before sharing because profile metadata can include your player name and logs can include local paths.

- If Factorio fails before MIR loads, include the engine log and crash output. The optional repository [support collector](scripts/Collect-MIRPlayerReport.cmd) can package redacted startup information without launching Factorio:

- Keep [Collect-MIRPlayerReport.cmd](scripts/Collect-MIRPlayerReport.cmd) beside [Collect-MIRPlayerReport.ps1](scripts/Collect-MIRPlayerReport.ps1), then double-click the `.cmd` file after the failed launch.
- It writes a `MIR-support-*.zip` beside the collector and copies its path to the clipboard; review the ZIP before sharing it.
- Run the PowerShell script with `-FactorioUserData` for a custom Factorio user-data folder or `-OutputDirectory` for a different output folder.

## Support limits

- MIR does not claim universal modpack support. A report is evaluated for its exact Factorio version, MIR package, mods, settings, save and observed behavior. The [support and upgrade guide](docs/support.md) explains edition limits, safe upgrades, recovery and diagnostic commands.
