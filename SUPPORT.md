# Support

- Report crashes, loading failures and problems with other mods using the [bug report form](https://github.com/Julesc013/more-infinite-research/issues/new?template=bug.yml). You can report a problem even if you cannot reproduce it. Use [SECURITY.md](SECURITY.md) for private security reports.

## Tell us what happened

- Describe what happened and what you expected.
- Include the Factorio and MIR versions if you know them; “not sure” is fine.
- Name other mods that seem involved, or attach a mod list.
- Give steps to reproduce it if known. There is no need to start a new save before reporting.
- Optional: add error text, a screenshot, `factorio-current.log`, a settings export or a small save. Check attachments for personal information before posting.

If you investigate further, preserve the original save and matching mods/settings, and test a copy.

## Useful exports

- On Factorio 2.0 and 2.1, Library **Settings → Export Settings** provides the full MIRSET1 profile and settings file. This helps us check your configuration. **Export Compact** omits defaults. **Debug → Export Diagnostics** replaces the latest MIR diagnostic report but does not replace Factorio's engine log.

- Exports are local and never upload anything automatically. They do not apply settings or change research. Review files before sharing because profile metadata can include your player name and logs can include local paths.

- If Factorio fails before MIR loads, the engine log and error text are useful; you do not need a Library export. The optional repository [support collector](scripts/Collect-MIRPlayerReport.cmd) can package startup information without launching Factorio.

- Keep [Collect-MIRPlayerReport.cmd](scripts/Collect-MIRPlayerReport.cmd) beside [Collect-MIRPlayerReport.ps1](scripts/Collect-MIRPlayerReport.ps1), then double-click the `.cmd` file after the failed launch.
- It writes a `MIR-support-*.zip` beside the collector and copies its path to the clipboard; review the ZIP before sharing it.
- Run the PowerShell script with `-FactorioUserData` for a custom Factorio user-data folder or `-OutputDirectory` for a different output folder.

## Support limits

- The [support and upgrade guide](docs/support.md) lists supported Factorio versions, known mod interactions, safe upgrades, recovery and diagnostic commands. Reports about other combinations are welcome; they help us investigate gaps.
