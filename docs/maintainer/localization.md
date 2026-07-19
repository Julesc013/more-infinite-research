---
title: "Localization Governance"
status: current
applies_to: "3.2.0+ and maintained backports"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-19
supersedes: []
superseded_by: []
---
# Localization Governance

MIR ships a complete locale file for every language directory supported by the qualified Factorio installation. English is the source authority; generated CFG files and per-language translation memories make omissions and stale prose mechanically visible.

## Authorities

| Authority | Purpose |
| --- | --- |
| `locale/en/more-infinite-research.cfg` | Canonical keys, section order, placeholders, rich-text tags, and English meaning. |
| `.mir/locales/manifest.json` | Supported Factorio locale set, translation codes, script expectations, and UI prose budgets. |
| `.mir/locales/translations/<locale>.json` | Complete per-key translations, English source hashes, and provenance. |
| `.mir/locales/overrides.json` | Small reviewed corrections for terminology or machine-draft values that need explicit wording. |
| `scripts/Update-MIRLocales.ps1` | Deterministic CFG and translation-memory generator. |
| `scripts/Test-MIRLocales.ps1` | Offline release gate for completeness, freshness, syntax, and prose constraints. |
| `scripts/localization/MIRLocalization.psm1` | Shared parser, writer, hashing, placeholder, rich-text, and length primitives. |

Files below `locale/<code>/` other than English are generated outputs. Change a translation-memory value or add a narrow override, then regenerate; do not leave a hand-edited CFG that differs from its memory.

## Normal Workflow

After changing English locale text:

```powershell
.\scripts\Update-MIRLocales.ps1
```

This intentionally fails and lists a language with missing or stale source hashes. A maintainer can translate those keys directly in the language memory or create machine-assisted drafts:

```powershell
.\scripts\Update-MIRLocales.ps1 -MachineTranslateMissing
.\scripts\Test-MIRLocales.ps1
```

Machine assistance is an initial completion mechanism, not a substitute for the exact-candidate `locale-fit-and-truncation` manual release item. Community or maintainer corrections should replace machine-assisted values in translation memory or the small override catalog and preserve the matching English source hash.

## Enforced Contract

The static locale gate requires:

- exactly the Factorio-supported locale directories recorded in the manifest;
- exact section/key parity with English for every language;
- one non-empty translation-memory row for every non-English key;
- an exact SHA-256 of the current English value on every translation row;
- byte equality between each memory value and its generated CFG value;
- exact placeholder order and exact Factorio rich-text tag order;
- no control characters, Unicode replacement characters, or empty values;
- no non-invariant value copied byte-for-byte from English;
- expected writing-system characters for non-Latin languages;
- section-specific visible-text budgets for names, choices, modifiers, and descriptions;
- explicit provenance: `preexisting`, `machine-assisted`, `maintainer-override`, or `format-invariant`.

Numeric percentages are format-invariant and may match English. Product names such as MIR and Factorio may remain inside translated prose, but they do not waive the target-script requirement.

## Review Standard

Automated acceptance proves structural integrity and freshness. Human review of a release candidate should still inspect:

- setting labels at normal UI scale;
- tooltip wrapping and truncation;
- technology names and descriptions in the technology tree;
- terminology consistency with Factorio's base locale;
- right-to-left readability and tag placement;
- placeholders rendered with representative values;
- narrow overrides and any remaining machine-assisted high-visibility strings.

Record findings against the exact candidate hash. A locale correction changes package bytes, so performance, manual, approved-delta, upgrade, and seal evidence must bind the rebuilt candidate.

## Branch And Release Policy

Localization tooling and portable translations flow from `dev` to maintained target branches. Target branches may omit only keys whose English source is absent on that target; they must still be complete against their own English authority. Published archives are immutable. Corrections for published versions require a new patch release and an independently rebuilt and qualified archive.
