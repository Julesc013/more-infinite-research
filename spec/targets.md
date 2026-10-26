---
title: "Engine targets, packaging and delivery"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-targets-specification
---

# Engine targets, packaging and delivery

`TGT-01` — One shared source, small actual engine adapters, one selected adapter per distribution. Do not retain parallel complete modern/legacy products. Historical editions keep their own delivered capability subsets; unsupported modifiers/UI cannot be manufactured by a generic runtime shim.

## Primary target and earlier editions

The maintainer's 2026-10-25 direction makes **Factorio 2.1 with minimum base 2.1.23 (F210)** the primary MIR5 design target and gives its implementation and qualification scheduling priority. Design new behavior against its actual native APIs and capabilities. Keep the small deterministic Generator and shared semantic implementations, with narrowly selected adapters for earlier engines.

Build F200 for 2.0.77 and the seven historical editions from the same shared implementation, retaining their delivered capability subsets, nine-edition version encoding and stable mod/technology/migration identities. Keep common feature behavior, setting identities and meanings, and presentation consistent where native capabilities permit; isolate engine differences in the selected adapters. Run final current-package and affected native checks for every delivered target subset before release, reusing exact unchanged evidence under its original inputs and verdicts. Earlier editions remain best-effort ports within their real native capabilities; F210 priority does not authorize an unqualified earlier edition or silently narrow the release scope. State unresolved gaps by edition; all applicable native, upgrade/save/client, performance and delivery requirements remain binding.

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

Use title `MIR MAJOR.MINOR.PATCH`, exact tested patch labels without `+`, the nine retained player ZIPs and any buildable explicitly labelled best-effort historical editions, plus useful checksum/signature files. Keep bundles, upload instructions and developer artifacts out of public player downloads unless expressly requested. Preserve full master history in packaged changelogs. Verify anonymous downloads and local delivery by bytes. Agent-managed publication is GitHub-only for all releases; the maintainer handles Mod Portal publication, credentials and readback, which are not agent completion gates.

Cryptographic identity and successful CI do not prove gameplay correctness. Release requires the separate parity, native/migration and performance outcomes in [Verification](verification.md).

## Reproducible source is not a wall-clock promise

`TGT-05` — Apply the package boundary in [Determinism](determinism.md). Compare member bytes independently from ZIP headers/compression. Keep rendered diagrams and optional diagram tooling out of player packages. The operating-system/runtime needed by developer tools does not determine which historical Factorio editions the mod supports.

## Additional historical editions

`TGT-06` — The maintainer's 2026-10-26 decision requests best-effort GitHub distributions for F001–F012 on each MIR release, ideally ready for5.0.0, while retaining F013–F210 implementation and qualification priority. These extras do not become Mod Portal obligations or silently expand the mandatory native matrix. Include honestly buildable artifacts with their exact feature subset, installation format, checks and missing qualification; do not manufacture invalid or empty ZIPs to fill target names. Qualified, built-but-unqualified and unresolved targets have distinct release labels. Preserve the same shared source and codec.

The requested engine patches are0.1.2,0.2.10,0.3.2,0.4.1,0.5.3,0.6.4,0.7.5,0.8.8,0.9.8,0.10.12,0.11.22 and0.12.35. F001/F002 have no evidenced standalone mod-loader contract; [0.3.0 introduced standalone mods](https://www.factorio.com/blog/post/factorio-030-released). F003–F005 have credible mod loading but lack supplied exact engine/prototype inputs and remain unresolved. No current native result establishes them. The installed-engine and preserved museum-tag facts for F006–F012 support a fixed-default finite, data-only adapter; they do not establish settings, runtime API, Library, migration or native-infinite parity. The opt-in target record keeps these builds outside the retained nine-edition freeze verdict.

Factorio0.18.47 is also visible in the [official history](https://wiki.factorio.com/Version_history/0.18.0). It was explicitly excluded from the inherited target baseline, has no installed engine input here and remains an unresolved additional-edition obligation under the request for every minor line. F100 packaging does not prove that a1.0-marked mod loads in0.18. Recover its actual constraints before admitting an F018 build; do not silently claim or omit it from the disposition.

## Shared release history

`TGT-07` — [CHANGELOG.md](../CHANGELOG.md) is the sole authored product history: the selected27 MIR1–3 master releases, then every MIR4 and MIR5 source release. Retain historical scope and unique corrections without repeating reduced backport release logs. Do not invent release dates. The small formatter projects this Markdown into [source/changelog.txt](../source/changelog.txt), with native separators, indentation, unique version sections and valid continuation lines. Only the leading current-release version is substituted by the packager. Every distribution receives the same complete master history; its presence does not claim that a historical edition existed in an earlier MIR release. The [reconciliation inventory](inventory/changelog-history.json) preserves original input identities.
