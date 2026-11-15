# Support

- Report crashes, loading failures and problems with other mods using the [bug report form](https://github.com/Julesc013/more-infinite-research/issues/new?template=bug.yml). You can report a problem even if you cannot reproduce it. Use [SECURITY.md](SECURITY.md) for private security reports.

## Tell us what happened

- Describe what happened and what you expected.
- Include the Factorio and MIR versions if you know them; “not sure” is fine.
- Name other mods that seem involved, or attach a mod list.
- Give steps to reproduce it if known. There is no need to start a new save before reporting.
- Optional: add error text, a screenshot, `factorio-current.log`, a settings export or a small save. Check attachments for personal information before posting.

Keep the original save and matching mods/settings. We retain the report and supplied files with its case, investigate the interaction, and test the repair. You do not need to remove mods one at a time, start over, or act as the release tester. If an essential detail is missing, we first check the material already supplied and explain the specific gap.

## Useful exports

- On Factorio 2.0 and 2.1, Library **Settings → Export Settings** provides the full MIRSET1 profile and settings file. This helps us check your configuration. **Export Compact** omits defaults. **Debug → Export Diagnostics** replaces the latest MIR diagnostic report but does not replace Factorio's engine log.

- Exports are local and never upload anything automatically. They do not apply settings or change research. Review files before sharing because profile metadata can include your player name and logs can include local paths.

- If Factorio fails before MIR loads, the engine log and error text are useful; you do not need a Library export. The optional repository support collector below works without launching Factorio. Missing runtime exports are expected after an early startup failure.

## Collect the available files in one ZIP

- Keep [Collect-MIRPlayerReport.cmd](scripts/Collect-MIRPlayerReport.cmd) beside [Collect-MIRPlayerReport.ps1](scripts/Collect-MIRPlayerReport.ps1), then double-click the `.cmd` file after the failed launch.
- It writes a `MIR-support-*.zip` beside the collector and copies its path to the clipboard; review the ZIP before sharing it.
- The ZIP includes available current/previous engine logs, the mod list, package identity hashes and existing MIR diagnostic/settings exports. It records installed MIR archives and bounded hashes of ZIP filenames matching mod versions observed in the current log. Oversized logs retain both their beginning and end; the manifest identifies missing, unreadable, truncated or omitted material. Installed or filename-matched package identities do not prove which bytes were active; unpacked and ambiguous selections remain unverified.
- Run the PowerShell script with `-FactorioUserData` for a portable/custom installation or `-OutputDirectory` for a different output folder. On Linux/macOS it requires an installed PowerShell (`pwsh`) and an explicit user-data directory; the `.cmd` convenience launcher is Windows-only.

For a settings-dependent or existing-save problem, you can include exact mod settings and a specifically selected original save in the same collection:

```powershell
.\Collect-MIRPlayerReport.ps1 -FactorioUserData 'C:\path\to\Factorio' -IncludeModSettings -SavePath 'C:\path\to\original-save.zip'
```

For an explicitly selected portable Linux installation, use its actual user-data directory:

```sh
pwsh -NoProfile -File ./Collect-MIRPlayerReport.ps1 -FactorioUserData /path/to/factorio-user-data -IncludeModSettings -SavePath /path/to/original-save.zip
```

- `-IncludeModSettings` includes the original `mods/mod-settings.dat`; `-SavePath` includes only the save you select. Neither option changes the original. Omit the save option for a failure that occurs before a save is opened.
- Raw settings are limited to 16 MiB. The selected-save limit defaults to 1024 MiB; use `-MaxSaveMiB` to select 1–4096 MiB. Inputs above the chosen limit are explicitly omitted in the manifest, and an incomplete requested capture prints a warning.
- Raw settings and saves can contain personal information. The full MIRSET1 profile is encoded and may also contain player metadata; it is not certified redacted. Common sensitive fields in readable logs are redacted, but review the archive and choose an appropriate private sharing method for exact inputs.
- No files are uploaded automatically. Other mod ZIPs, credentials, crash dumps and unrelated saves are not collected. A missing or truncated input remains a limitation, not a claim that the original configuration can be reproduced.

## Suggestions

Describe the outcome you want and how you would use it in the [feature form](https://github.com/Julesc013/more-infinite-research/issues/new?template=feature.yml). We record the decision, define the acceptance criteria for accepted work, and own implementation and verification. You do not need to design the code or manage the work after reporting it.

## Support limits

- The [support and upgrade guide](docs/support.md) lists supported Factorio versions, known mod interactions, safe upgrades, recovery and diagnostic commands. Reports about other combinations are welcome; they help us investigate gaps.
