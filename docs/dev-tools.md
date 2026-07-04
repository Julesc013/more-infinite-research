# Developer Tools

This repository has a small MIR developer test harness. It is not a separate product or a second framework. The goal is to keep common release, audit, package, and report tasks behind short commands while preserving the existing scripts as the implementation engines.

## Preferred Commands

Use `scripts/mir.ps1` first:

```powershell
.\scripts\mir.ps1 release gate
.\scripts\mir.ps1 overnight local
.\scripts\mir.ps1 audit local
.\scripts\mir.ps1 audit top25 --space-age
.\scripts\mir.ps1 report latest
.\scripts\mir.ps1 report missing-deps --run <path>
.\scripts\mir.ps1 package build
.\scripts\mir.ps1 local-index build --mods <path>
```

Common overrides:

```powershell
--factorio <path>
--mods <path>
--output <path>
--timeout <seconds>
--profile <profile-name-or-path>
```

`mir.ps1` delegates to the existing scripts. It should stay thin: argument routing, profile loading, and memorable command names. Do not add new compatibility logic directly to it.

## Run Profiles

Reusable defaults live in `fixtures/run-profiles/`.

| Profile | Purpose |
| --- | --- |
| `release-targeted` | Strict release gate plus targeted local smokes and package checks. |
| `overnight-local-2.1` | Bedtime offline local-library sweep for the Factorio 2.1 line. |
| `local-audit-2.1` | Offline local-library audit tiers without the strict release gate. |
| `local-bz-smoke` | Narrow BZ Space Age local smoke. |
| `top25-space-age` | Credentialed top-25 Space Age compatibility audit. |

Prefer adding or editing a profile over hardcoding paths in `mir.ps1`. Local machine paths are acceptable in profiles because they are explicit operator defaults and easy to override.

## Script Roles

Preferred public front door:

```text
scripts/mir.ps1
```

Stable direct commands:

```text
scripts/Invoke-MIRReleaseTargetedGate.ps1
scripts/Start-MIROvernightLocalSweep.ps1
scripts/Show-MIROvernightSummary.ps1
scripts/Build-MIRPackage.ps1
scripts/Invoke-MIRValidation.ps1
```

Advanced engines:

```text
scripts/Invoke-MIRExtendedTests.ps1
scripts/Invoke-MIRCompatAudit.ps1
scripts/Convert-MIRCompatAuditResults.ps1
scripts/New-MIRCompatProfileStub.ps1
```

Private helpers:

```text
scripts/MIRCli/*.ps1
scripts/MIRCompatAudit/*.ps1
```

The helper folders are not an architecture project to finish before useful work can happen. Use them when two or more scripts need the same behavior. Avoid creating new wrapper scripts unless a new human workflow genuinely needs one.

## Quality Checks

`scripts/Test-MIRPowerShellQuality.ps1` validates the PowerShell tooling surface:

- every `scripts/**/*.ps1` file parses;
- parameter blocks do not contain duplicate parameter names;
- generated output directories remain ignored;
- obvious credential-output lines are rejected;
- PSScriptAnalyzer is reported if installed, but it is not required.

Static validation runs this check:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Run it directly when working only on tooling:

```powershell
.\scripts\Test-MIRPowerShellQuality.ps1
```

## Design Rule

Keep the system boring:

```text
mir.ps1 = user-facing command names
run profiles = reusable defaults
existing scripts = engines
MIRCli = small private helper folder
```

Do not add more scenario types, reports, or framework modules until a real repeated pain point requires them.
