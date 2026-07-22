---
title: "Asset Sources"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---
# Asset Sources

This file records local image assets packaged by More Infinite Research. Generated technology icons should normally borrow active Factorio prototype icons at data stage instead of copying Wube asset files into this mod.

| Path | Source | Redistribution note |
| --- | --- | --- |
| `thumbnail.png` | More Infinite Research package thumbnail. | Project-owned presentation asset; not copied from Space Age. |
| `fixtures/museum/synthetic-installation/data/base/graphics/technology/bullet-damage.png` | Repository-authored 30-byte placeholder PNG for deterministic museum renderer tests; SHA-256 `CE26833BDA318FE96672CE9097E96619E8CB3C3177BB4FA388EE854586303A59`. | Project-owned synthetic test fixture under the repository license; excluded from the release ZIP and not copied from Factorio. |
| `fixtures/museum/synthetic-installation/data/base/graphics/technology/bullet-speed.png` | Repository-authored 29-byte placeholder PNG for deterministic museum renderer tests; SHA-256 `59557F069ABA49EB9C97D84A2E737C76B910CBD535E2DED7728EFE545F239DCB`. | Project-owned synthetic test fixture under the repository license; excluded from the release ZIP and not copied from Factorio. |
| `fixtures/museum/synthetic-installation/data/base/graphics/technology/character-logistic-trash-slots.png` | Repository-authored 47-byte placeholder PNG for deterministic museum renderer tests; SHA-256 `2BFCFD5E521CF1ADE5D5E9544BA4C78408DB565014C25E15AC3E25EFFDE33A5D`. | Project-owned synthetic test fixture under the repository license; excluded from the release ZIP and not copied from Factorio. |
| `fixtures/museum/synthetic-installation/data/base/graphics/technology/gun-turret-damage.png` | Repository-authored 34-byte placeholder PNG for deterministic museum renderer tests; SHA-256 `ADA592F7242497213DD953CF77EF3EB178579912F2FAC23278A60CEEFFADD7DB`. | Project-owned synthetic test fixture under the repository license; excluded from the release ZIP and not copied from Factorio. |
| `fixtures/museum/synthetic-installation/data/base/graphics/technology/inserter-stack-size-bonus.png` | Repository-authored 42-byte placeholder PNG for deterministic museum renderer tests; SHA-256 `5A8F7A873ED1170357A4634A735CC2A7620104BA8D430FC1B6043FCF2A448F7A`. | Project-owned synthetic test fixture under the repository license; excluded from the release ZIP and not copied from Factorio. |
| `fixtures/museum/synthetic-installation/data/base/graphics/technology/toolbelt.png` | Repository-authored 25-byte placeholder PNG for deterministic museum renderer tests; SHA-256 `81A33E26B2CE62BEF903B6924515DF171522167844484C181F34F0DE70CC5530`. | Project-owned synthetic test fixture under the repository license; excluded from the release ZIP and not copied from Factorio. |
| `.mir/evidence/3.1.0-interactive-save-loaded.png` | Local Factorio 2.1.9 screenshot captured during the MIR 3.1.0 interactive release review. | Validation evidence only; excluded from the release zip and not presented as a redistributable game asset. |
| `.mir/evidence/3.1.0-interactive-mod-settings.png` | Local Factorio 2.1.9 screenshot captured during the MIR 3.1.0 interactive release review. | Validation evidence only; excluded from the release zip and not presented as a redistributable game asset. |
| `.mir/evidence/3.1.0-interactive-technology.png` | Local Factorio 2.1.9 screenshot captured during the MIR 3.1.0 interactive release review. | Validation evidence only; excluded from the release zip and not presented as a redistributable game asset. |

Policy:

- Do not copy original Space Age PNGs or other DLC asset files into this mod as base-only fallbacks.
- Direct official DLC icon references such as `__space-age__` or `__elevated-rails__` are allowed only as prototype paths gated by `mir-use-installed-space-age-icons`; they are not packaged assets.
- Target-line fallback overlays should reference assets already present in the active Factorio install. Prefer the same high-resolution stock core technology badge layers used by the target game's own technology helpers, such as `__core__/graphics/icons/technology/constants/*`, for technology tile overlays. The smaller `__core__/graphics/icons/technology/effect-constant/*` sprites are effect row utility art and should not be used as technology tile badges unless a target line has no high-resolution equivalent and the substitution is documented.
- If a target line has no separate technology constant/control icon assets and no documented native modifier icon surface, do not simulate badges from unrelated technology art. Use the best target-era main technology texture and locale text instead.
- Any future MIR-owned or third-party local art must be added to this table with an explicit source and redistribution note before package validation can pass.
