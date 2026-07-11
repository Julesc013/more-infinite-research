---
title: "Validation"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: ["testing.md"]
superseded_by: []
---

# Validation

Run static validation:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Run narrow governance checks first when the change is scoped:

```powershell
.\scripts\mir.ps1 docs check
.\scripts\mir.ps1 manifests check
.\scripts\mir.ps1 architecture check
```

Run runtime validation when a Factorio binary is available:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\path\to\factorio.exe"
```

## Structured Runtime Results

A runtime run writes an atomic JSON summary to
`artifacts/validation/factorio-<line>-summary.json`. Override that location
with `-ValidationSummaryPath` or `MIR_VALIDATION_SUMMARY`. The output remains
outside release packages and records:

- the target profile's required groups;
- every started scenario, its group, duration, and evidence paths;
- `passed`, `failed`, `skipped`, or `incomplete` group status;
- the currently running scenario, if the process is interrupted;
- the complete run duration and terminal error, when available.

Scenario groups are classified by `scripts/validation/ScenarioGroups.ps1`.
The runner persists a `running` scenario before Factorio starts and updates it
after the process and log checks finish. Therefore an external timeout leaves
an `incomplete` record instead of being reported as a failed Factorio load.
An observed nonzero exit, fatal log marker, or assertion is a failure.

The final gate calls `Complete-MIRValidationRun`, which rejects any required
target-profile group that did not pass. `scripts/Test-MIRValidationResults.ps1`
checks both complete and interrupted result shapes during static validation.

## Reproducible Candidate Fingerprints

Package-source, packaged-content, validation-harness, and expected-scenario
fingerprints normalize text files to UTF-8 with LF line endings before hashing.
This makes one clean Git commit retain the same content identity under LF and
CRLF checkout policy. Binary files and the final release archive remain
byte-exact SHA-256 inputs.

`scripts/Test-MIRPackageIdentity.ps1` proves that LF and CRLF copies produce
matching semantic fingerprints, that binary/archive byte hashes remain exact,
and that a real text change still changes the package identity.
