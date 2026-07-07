---
title: "Developer Tools"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# Developer Tools

This repository has a small MIR developer test harness. It is not a separate product or a second framework. The goal is to keep common release, audit, package, and report tasks behind short commands while preserving the existing scripts as the implementation engines.

## Preferred Commands

Use `scripts/mir.ps1` first:

```powershell
.\scripts\mir.ps1 docs check
.\scripts\mir.ps1 architecture check
.\scripts\mir.ps1 manifests check
.\scripts\mir.ps1 release gate
.\scripts\mir.ps1 release docs-only
.\scripts\mir.ps1 release docs-refresh
.\scripts\mir.ps1 overnight local
.\scripts\mir.ps1 audit local
.\scripts\mir.ps1 audit top25 --space-age
.\scripts\mir.ps1 report latest
.\scripts\mir.ps1 report missing-deps --run <path>
.\scripts\mir.ps1 report observations --run <path>
.\scripts\mir.ps1 package build
.\scripts\mir.ps1 local-index build --mods <path>
.\scripts\Test-MIRPolicyLints.ps1
.\scripts\Compare-MIRPlannerReports.ps1 -Before <old-run> -After <new-run>
```

Common overrides:

```powershell
--factorio <path>
--factorio-line <2.0|2.1>
--mods <path>
--output <path>
--timeout <seconds>
--profile <profile-name-or-path>
```

`mir.ps1` delegates to the existing scripts. It should stay thin: argument routing, profile loading, and memorable command names. Do not add new compatibility logic directly to it.

`release docs-only` and `release docs-refresh` are aliases for the fast
post-gate documentation path. Use them only after the current release candidate
has already passed the full release gate and the remaining edits are docs,
release notes, changelog text, or the release archive. The command rebuilds the
package, runs static/package validation, checks whitespace, and rejects
non-doc/package changes so code, prototype, script, fixture, or locale edits
still require the full release gate.

`report observations` summarizes `compat-observations.csv` rows produced by the
audit converter. Use it to see diagnostics-only planner rows and recipe-cap
warnings without treating them as failures or profile candidates.

`Test-MIRPolicyLints.ps1` is the static policy gate for the procedural
compatibility kernel. It checks resolver contract wiring, capability policy,
generated stream manifest fields, support-lane fixtures, compatibility claims,
and broad public-claim wording.

`Compare-MIRPlannerReports.ps1` compares two runs that contain
`compat-observations.json`. Use it after changing classifier, policy, or
compatibility fixture behavior to see new and removed generated streams,
capability decisions, unknown candidates, loop risks, owner rows,
science/lab rows, cap diagnostics, and claim-level entries.

## Run Profiles

Reusable defaults live in `fixtures/run-profiles/`.

| Profile | Purpose |
| --- | --- |
| `release-targeted` | Strict release gate plus targeted local smokes and package checks. |
| `release-targeted-2.1` | Explicit Factorio 2.1 release-gate profile. |
| `release-targeted-2.0` | Legacy-line release-gate profile for a backported source tree. |
| `overnight-local-2.1` | Bedtime offline local-library sweep for the Factorio 2.1 line. |
| `overnight-local-2.0` | Bedtime offline local-library sweep for the Factorio 2.0 line. |
| `local-audit-2.1` | Offline local-library audit tiers without the strict release gate. |
| `local-audit-2.0` | Offline local-library audit tiers for a Factorio 2.0 local library. |
| `local-bz-smoke` | Narrow BZ Space Age local smoke. |
| `top25-space-age` | Credentialed top-25 Space Age compatibility audit. |

Run `Test-MIRLocalModLibraryCatalog.ps1` before expensive local sweeps to verify
that the local zip library contains the root mods named by the committed
local-library scenario file. This is metadata-only; it does not launch Factorio
or call the Mod Portal.

Prefer adding or editing a profile over hardcoding paths in `mir.ps1`. Local machine paths are acceptable in profiles because they are explicit operator defaults and easy to override.

`FactorioLine` is a selector for the existing tools, not a separate harness. It controls Mod Portal release matching, local scenario defaults, output naming, and which local library path is chosen when no path is passed. A Factorio `2.0` profile still requires a real Factorio `2.0.x` binary and a source tree whose `info.json` targets Factorio `2.0`.

Local audit profiles distinguish roots from libraries:

- `local_mod_zip_dirs` lists root mods that may become one-mod, curated, or generated local scenarios.
- `local_mod_library_dirs` lists dependency libraries used to close those scenarios offline.
- Generated local scenarios are built only from root zips, not dependency-only library zips.

Use a writable dependency-cache library for downloaded prerequisites instead of changing the read-only mod collection. For large local audits, prefer an output path on a roomy drive and choose a staging mode explicitly:

```powershell
.\scripts\mir.ps1 run -Profile local-audit-2.1 --output F:\Factorio\mir-artifacts\local-audit-2.1 --link-mode Copy
```

`--link-mode Hardlink` can reduce copy time and disk usage when source zips and scenario folders are on the same drive. `Copy` is the safest cross-drive mode.

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
scripts/Test-MIRArchitecture.ps1
```

Advanced engines:

```text
scripts/Invoke-MIRExtendedTests.ps1
scripts/Invoke-MIRCompatAudit.ps1
scripts/Convert-MIRCompatAuditResults.ps1
scripts/New-MIRCompatProfileStub.ps1
scripts/Test-MIRPolicyLints.ps1
scripts/Compare-MIRPlannerReports.ps1
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
