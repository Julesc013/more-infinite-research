---
title: "MIR 4 change and release narrative authority"
status: current
audience: developer
doc_type: explanation
owner: mir-maintainers
applies_to: "MIR 4.x"
supersedes: []
superseded_by: []
last_reviewed: 2026-08-31
generated_from: []
---

# MIR 4 change and release narrative authority

MIR 4 uses accepted JSON change fragments under `changes/unreleased/` as the only mutable authority for release changes. Released fragments move to `changes/history/<source-version>/`; they remain typed historical facts rather than hand-maintained prose. Commit history, filenames, GitHub state, and old release copy are inputs or references, never substitute change authorities.

The `MIR4ChangeFragmentV2` contract requires a stable ID, curated summary, semantic domains, audiences, exact target dispositions, package visibility, save/settings/migration/compatibility/contract/support impacts, disclosure policy, and an explicit disposition for every release surface. An `unknown` target or impact blocks source freeze. Embargoed records may render only the standard redaction until a separate disclosure authority changes their accepted disposition.

## Renderer boundary

The release-narrative application receives one immutable plan plus an accepted fragment set. Six focused renderers produce:

- source `CHANGELOG.md`;
- target-specific Factorio `changelog.txt`;
- a GitHub Release body;
- target-specific Mod Portal text;
- a technical release record;
- the release-manifest change inventory.

Renderers filter only on typed target and surface dispositions. They do not inspect Git history, infer applicability from paths, query GitHub for product semantics, invent support or upgrade claims, write package files, or discover additional changes. A target with `unchanged-no-package` or `omitted` action produces no target output.

The supported command is:

```powershell
.\tools\mir.ps1 mir4 release-narratives render --plan <plan.json> --output <directory>
.\tools\mir.ps1 mir4 release-narratives check --plan <plan.json> --output <directory>
```

Every run validates the plan and fragments, rejects duplicate identities and unresolved dispositions, renders twice in memory, checks public-copy and Factorio-format rules, records exact output hashes, and proves the package-source fingerprint remains unchanged. Its result grants no merge, version allocation, tag, signing, sealing, or publication authority.

## Historical and synthetic proof

MIR 4.0.0 is imported as a semantic historical corpus. Its shadow render uses the exact preserved target distributions and public asset names but does not rewrite the GitHub Release, tag, packages, or historical campaign language. Semantic equivalence is required; undesirable old prose is not reproduced.

Synthetic corpora prove an F210-only patch, a multi-target compatible feature, a repository-only change, a migration, an embargoed security correction, and target capability omissions. They are fixtures only and do not allocate MIR 4.0.1 or MIR 4.1.0.
