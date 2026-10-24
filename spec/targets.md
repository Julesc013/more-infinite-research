---
title: "Engine targets, packaging and delivery"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-targets-specification
---

# Engine targets, packaging and delivery

`TGT-01` — One shared source, small actual engine adapters, one selected adapter per distribution. Do not retain parallel complete modern/legacy products. Historical editions keep their own delivered capability subsets; unsupported modifiers/UI cannot be manufactured by a generic runtime shim.

## Baseline targets, not new qualification

The previous release records identify these nine target editions. Their identifiers/version encoding are retained until an explicitly tested change replaces them. These are **baseline test floors**, not fresh replacement acceptance or an installed-engine inventory.

| Target | Baseline engine |
|---|---|
| F013 | 0.13.20 |
| F014 | 0.14.23 |
| F015 | 0.15.40 |
| F016 | 0.16.51 |
| F017 | 0.17.79 |
| F100 | 1.0.0 |
| F110 | 1.1.110 |
| F200 | 2.0.77 |
| F210 | 2.1.23 |

Verify each current executable, official mods and consumed API against the actual local environment. The inherited source recorded 2.1.14 documentation; this revision observed official latest pages labelled 2.1.23. Neither observation is native qualification. Exact-version URL retrieval was unavailable; native work must pin and record the consumed target documentation. Do not silently chase a newer experimental binary during a frozen comparison.

`TGT-02` — `factorio_version` is the family and the `base >= x.y.z` dependency is the declared patch minimum. Preserve the distribution codec `100 * target_code + source_patch`, padded to five digits, unless deliberately replaced with full migration/release review. Patch digits are not RC/build counters. Check internal root, archive filename, info metadata, changelog and release label together. [Mod structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

## Package contract

A packager copies known player source/assets, selects actual adapter files, applies explicit metadata and creates a deterministic ZIP. It does not infer research. Keep the Factorio mod identity unchanged. Package member paths are **relative to the selected player root**; they never contain repository prefixes such as `source/` or the staging directory.

`TGT-03` — Player ZIP membership is an allowlist: necessary Lua, locale, graphics, migration files, metadata, license and complete applicable changelog. Exclude tests, docs, SDK, schemas, plans, inventories, evidence, local caches and agent tools. A working development root is not automatically a package boundary.

Keep case-correct portable paths, LF Lua/Markdown where appropriate, tested CRLF host fixtures, no absolute machine paths in player data, and no unavailable syntax/API imports on old targets. Preserve required asset licenses and attribution. Reuse base/expansion icons only when that asset is guaranteed available for the profile or a verified fallback exists.

A pure directory cutover must produce identical package **member paths and bytes** for each frozen target. ZIP container bytes also match when its timestamps/order/compression environment are pinned. Otherwise explain container-only differences; source-path relocation is not a reason to change gameplay data or filenames.

## Release

`TGT-04` — Promote accepted development through `dev` then `main` using the existing permissions and required checks. This specification does not authorize changing branch protection, signing, release immutability settings or credentials. Preserve prior releases and provenance; repository cleanup must not rewrite tags.

Use title `MIR MAJOR.MINOR.PATCH`, exact tested patch labels without `+`, nine applicable player ZIPs plus useful checksum/signature files, and no redundant downloads table. Keep bundles, upload instructions and developer artifacts out of public player downloads unless expressly requested. Preserve full history in packaged changelogs. Verify anonymous downloads and local delivery by bytes; GitHub publication is distinct from Mod Portal publication.

Cryptographic identity and successful CI do not prove gameplay correctness. Release requires the separate parity, native/migration and performance outcomes in [Verification](verification.md).

## Reproducible source is not a wall-clock promise

`TGT-05` — Apply the package boundary in [Determinism](determinism.md). Compare member bytes independently from ZIP headers/compression. Keep rendered diagrams and optional diagram tooling out of player packages. The operating-system/runtime needed by developer tools does not determine which historical Factorio editions the mod supports.
