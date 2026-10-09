---
title: "MIR 4 Inspector Preview"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-07
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-inspector-developer-guide
---

# MIR 4 Inspector preview

Inspector renders bounded, immutable inspection bundles and exact snapshot comparisons. Extract `mir4-inspector-v1-preview.zip`, generate or select a bundled inspection bundle, and open its local HTML entry point.

Check the target, environment digest, source digest, availability state, diagnostic order, and comparison basis before interpreting a difference. `UNKNOWN` is preserved and is never displayed as safe or absent.

The current browser and standalone PowerShell exporter templates share the governed inspection bounds: eleven sections, at most 100 entries in an array, UTF-8 strings of at most 4,096 bytes, and object/array containers through depth eight. Primitive leaves below the deepest allowed container remain valid; the bundled canonical snapshot exercises that boundary. Both consumers reject forbidden fields, duplicate section identities, incorrect counts and changed read-only headers. Local parsing and export additionally have an 8 MiB byte ceiling and at most 100 properties per object. A rejected PowerShell input preserves any existing output file.

Run `tests/inspection/Test-MIR4InspectorExportConsumers.ps1` to exercise the generated exporter with the actual reference snapshot and opposing inputs. When Node is available, it also executes the generated browser validator with the same vectors. The retained vectors support a separate V8 host when Node is unavailable. These checks cover the validator and export path; they do not establish physical browser interaction or authenticate a record's declared digests. Refresh the committed SDK projections through `tools/commands/mir4/Invoke-MIR4PlatformPreview.ps1 -Command generate` before assembling corrected preview assets.

Inspector is read-only. It cannot mutate a save, run a migration, change a prototype, accept a compatibility claim, or authorize release.
