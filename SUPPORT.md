# Support

Open a GitHub issue for reproducible player problems and extension-tooling defects. Security concerns use [the private security route](SECURITY.md).

## Include exact evidence

Provide:

- MIR player distribution version and exact edition/engine family;
- Factorio version;
- the exact mod list, inherited startup settings and relevant MIR diagnostics;
- expected and observed behavior;
- whether the issue reproduces in a new save;
- relevant Factorio log and crash output with secrets and personal paths removed.

Include the original input identities and preserve the failing log and save separately. Historical MIR4 SupportBundleV1 tooling is not the current MIR5 diagnostic contract. Do not upload save files, full mod archives, or private data unless a maintainer asks through an appropriate channel.

On modern MIR5 candidates, Library **Settings → Export Settings** shows the full MIRSET1 string and writes `script-output/more-infinite-research/settings/mir-settings-profile.txt`. Full export is the support default; compact profiles inherit omitted defaults. **Debug → Export Diagnostics** replaces the bounded `script-output/more-infinite-research/mir.log` snapshot and exports full settings through the same implementation. These exports do not apply settings or change research. Attach `factorio-current.log` separately for the complete engine session, especially failures before MIR loads. Review exports before sharing: settings metadata includes `exported_by`, and engine logs can contain usernames and local paths. No export uploads anything. See [safe diagnosis](docs/support.md#safe-diagnosis) for commands, validation and exact limits.

If Factorio crashes before MIR loads, the optional repository [MIR support collector](scripts/Collect-MIRPlayerReport.cmd) can collect the engine-managed files. Keep it beside its [PowerShell script](scripts/Collect-MIRPlayerReport.ps1), then double-click it after the failed launch; it writes a `MIR-support-*.zip` beside the collector and copies its path to the clipboard. The PowerShell script also accepts `-FactorioUserData` for a custom user-data directory and `-OutputDirectory` for a chosen destination. It reads files without launching Factorio or requiring the MIR interface. The report contains redacted current/previous logs, the mod list, and MIR ZIP hashes. It records the binary startup-settings file's hash without including that file. Review the ZIP before sharing it. This small startup report helps triage a load failure; it is not a formal SupportBundleV1 or a substitute for exact settings when a maintainer needs them.

## Claim boundary

MIR does not claim universal modpack support. A support result is exact to its target, environment, MIR build, proposition, and evidence. The safe result may be applied, adopted, preserved, extension-required, review-required, omitted, or failed-hard-safety.

MEP/API/SDK/Inspector/ProcessIR are MIR 4.0 developer previews. Their contracts and conformance horizon are documented, but they do not grant player emission or stable public SDK 1.0 authority.

The current [MIR5 support and upgrade guide](docs/support.md) describes candidate editions, first-upgrade precautions and exact evidence limits. Original published MIR4 preview contracts remain available through their pinned historical Git refs.
