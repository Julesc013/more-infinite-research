---
title: "Engine targets, packaging and delivery"
status: current
applies_to: "MIR development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-30
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-targets-specification
---

# Engine targets, packaging and delivery

`TGT-01` — One shared source, small actual engine adapters, one selected adapter per distribution. Do not retain parallel complete modern/legacy products. Historical editions keep their own delivered capability subsets; unsupported modifiers/UI cannot be manufactured by a generic runtime shim.

## Primary target and earlier editions

The maintainer's 2026-10-27 clarification sets this implementation and qualification scheduling order. Targets in one row share priority.

| Priority | Editions |
|---|---|
| 1 — Primary | F210, Factorio 2.1.23 |
| 2 — Secondary | F200, Factorio 2.0.77 |
| 3 — Tertiary | F110 and F100 |
| 4 | F018 (experimental) through F013 |
| 5 | F012 through F006 |
| 6 | F005 through F003 |
| 7 | F002 and F001 |

MIR5 completion takes precedence over speculative additions. Parity, useful support for current mods and technologies, performance, stability and compatibility drive the remaining work. Maintainability and future expansion guide the shared source, authored definitions, narrow adapters and supported API; they do not require a new general framework. Design primarily against F210's actual native APIs and capabilities, keeping the small deterministic Generator.

Choose the next ready task using this order. Independent lower-priority preparation may proceed while a higher-priority assignment runs or awaits indispensable inputs, provided it does not delay that assignment or compete for its resources. Scheduling priority does not change edition scope, supported capability subsets or release acceptance.

Build the nine stable editions—F013–F017, F100, F110, F200 and F210—from the same shared implementation, retaining their delivered capability subsets, the existing edition version encoding and stable mod/technology/migration identities. Keep common feature behavior, setting identities and meanings, and presentation consistent where native capabilities permit; isolate engine differences in the selected adapters. Run final current-package and affected native checks for every stable delivered target subset before release, reusing exact unchanged evidence under its original inputs and verdicts. F018 remains selected by the ordinary target record and shared implementation, but is permanently GitHub-only experimental/best effort; it is not a tenth stable or Portal edition. F006–F012 remain separately labelled best-effort builds. F210 priority does not authorize an unqualified stable edition or silently narrow the release scope. State unresolved gaps by edition; all applicable stable-edition native, upgrade/save/client, performance and delivery requirements remain binding.

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

`TGT-02` — `factorio_version` is the family and the `base >= x.y.z` dependency is the declared patch minimum. Authored source, changelog and tag versions remain source versions; GitHub distribution ZIPs preserve the extended codec `100 * target_code + source_patch`, padded to five digits, unless deliberately replaced with full migration/release review. Patch digits are not RC/build counters. Both GitHub and Mod Portal use those same tested ZIPs and versions; there is no Portal-only conversion. Check internal root, archive filename, info metadata, changelog and release label together. [Mod structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

## Package contract

A packager copies known player source/assets, selects actual adapter files, applies explicit metadata and creates a deterministic ZIP. It does not infer research. Keep the Factorio mod identity unchanged. Package member paths are **relative to the selected player root**; they never contain repository prefixes such as `source/` or the staging directory.

`TGT-03` — Player ZIP membership is an allowlist: necessary Lua, locale, graphics, migration files, metadata, license and complete applicable changelog. Exclude tests, docs, SDK, schemas, plans, inventories, evidence, local caches and agent tools. A working development root is not automatically a package boundary.

Keep case-correct portable paths, LF Lua/Markdown where appropriate, tested CRLF host fixtures, no absolute machine paths in player data, and no unavailable syntax/API imports on old targets. Preserve required asset licenses and attribution. Reuse base/expansion icons only when that asset is guaranteed available for the profile or a verified fallback exists.

A pure directory cutover must produce identical package **member paths and bytes** for each frozen target. ZIP container bytes also match when its timestamps/order/compression environment are pinned. Otherwise explain container-only differences; source-path relocation is not a reason to change gameplay data or filenames.

### Source releases and shared channel artifacts

The maintainer's 2026-10-30 decision retains one source version `MAJOR.MINOR.PATCH`, one canonical tag `vMAJOR.MINOR.PATCH` and the existing edition package codec. For source5.0.2, F013/F017/F100/F110/F200/F210 are5.0.01302/5.0.01702/5.0.10002/5.0.11002/5.0.20002/5.0.21002. Source patch numbers00–99 advance only when publishing a new release, not for builds, commits, merges or tests. After patch99, select a new minor line; do not overflow into another edition code or reuse a published number.

GitHub's prerelease flag records maturity separately from the version/tag. Any source release may be a prerelease or stable; no beta count, RC stage, version suffix or minimum prerelease sequence is required. A prerelease is GitHub-only and must disclose its actual qualification and remaining limits. The maintainer authorizes the first `v5.0.0` GitHub beta with unfinished Library input/export/personal-view checks and performance testing explicitly deferred to stable. Package integrity, exact source/package/controller provenance, upgrade safety, normal checked publication and completed/failed/unverified disclosure remain mandatory; a known package or upgrade-safety defect still blocks the beta. Stable release acceptance remains the complete applicable contract. A numeric tag alone does not establish maturity; distribution automation and documentation must use the release metadata.

Each public version identifies one fixed package set. Never replace its published ZIPs with different bytes. Retain exact source/target/controller identities, complete member maps, hashes and verification evidence. Mutable GitHub release records do not authorize rewriting published package contents or moving their tags. Reconcile an interrupted publication by its existing release/asset IDs and hashes.

For a stable release, the maintainer uploads the identical qualified GitHub ZIPs for the nine Portal editions, with the same filenames, roots, info versions, runtime distribution literals, changelog and checksums. No export/rebuild or channel-specific numbering is needed. F018 and F001–F012 remain GitHub-only under their existing experimental/best-effort limits. Historical MIR4 mappings and previously recorded artifacts remain unchanged in their exact Git references; the former compact-copy converter is retired.

## Release

`TGT-04` — Promote accepted development through `dev` then `main` using the existing permissions and required checks. This specification does not authorize changing branch protection, signing, release immutability settings or credentials. Preserve prior releases and provenance; repository cleanup must not rewrite tags.

Use title `MIR MAJOR.MINOR.PATCH`, exact tested patch labels without `+`, the nine stable player ZIPs and any buildable explicitly labelled best-effort historical editions, including experimental F018, plus useful checksum/signature files. Keep bundles, upload instructions and developer artifacts out of public player downloads unless expressly requested. Preserve full master history in packaged changelogs. Verify anonymous downloads and local delivery by bytes. Agent-managed publication is GitHub-only for all releases; the maintainer handles upload of the identical qualified stable ZIPs, credentials and Portal readback, which are not agent completion gates. F018 is never a Portal deliverable.

Cryptographic identity and successful CI do not prove gameplay correctness. Stable release requires the separate parity, native/migration and performance outcomes in [Verification](verification.md); the authorized first `v5.0.0` GitHub beta may instead disclose unfinished Library input/export/personal-view checks and performance tests, while retaining its package, provenance, upgrade-safety and checked-publication gates.

## Reproducible source is not a wall-clock promise

`TGT-05` — Apply the package boundary in [Determinism](determinism.md). Compare member bytes independently from ZIP headers/compression. Keep rendered diagrams and optional diagram tooling out of player packages. The operating-system/runtime needed by developer tools does not determine which historical Factorio editions the mod supports.

## Additional historical editions

`TGT-06` — The maintainer's 2026-10-26 decision requests best-effort GitHub distributions for F001–F012 on each MIR release, ideally ready for5.0.0, while retaining F013–F017, F100, F110, F200 and F210 implementation and qualification priority. These extras do not become Mod Portal obligations or silently expand the mandatory native matrix. Include honestly buildable artifacts with their exact feature subset, installation format, checks and missing qualification; do not manufacture invalid or empty ZIPs to fill target names. Qualified, built-but-unqualified and unresolved targets have distinct release labels. Preserve the same shared source and codec.

The requested engine patches are0.1.2,0.2.10,0.3.2,0.4.1,0.5.3,0.6.4,0.7.5,0.8.8,0.9.8,0.10.12,0.11.22 and0.12.35. F001/F002 have no evidenced standalone mod-loader contract; [0.3.0 introduced standalone mods](https://www.factorio.com/blog/post/factorio-030-released). F003–F005 have credible mod loading but lack supplied exact engine/prototype inputs and remain unresolved. No current native result establishes them. The installed-engine and preserved museum-tag facts for F006–F012 support a fixed-default finite, data-only adapter; they do not establish settings, runtime API, Library, migration or native-infinite parity. The opt-in target record keeps these builds outside normal-edition qualification verdicts.

Factorio0.18.47 is also visible in the [official history](https://wiki.factorio.com/Version_history/0.18.0). F018 remains selected by the ordinary target record with minimum0.18.47 and codec01800 for source5.0.0, but is permanently a GitHub-only experimental/best-effort distribution alongside F001–F012, not a stable or Portal edition. Reuse the shared F100 implementation/test mechanisms and compatible inputs where their actual contracts match, but an F100 result is not an F018 native result. Retain established0.18 API/prototype differences; do not rewrite third-party archive metadata to force F100 dependencies onto0.18. F018's only target-specific acceptance scope is correct metadata/package information plus an actual0.18 native load/crash smoke; it does not require save, modpack, science, client or performance campaigns. Record any missing engine/input explicitly without blocking the nine stable editions or their eventual stable Portal upload. This is a limited delivery contract, not a new pass.

## Shared release history

`TGT-07` — [CHANGELOG.md](../CHANGELOG.md) is the sole authored product history: the selected27 MIR1–3 master releases, then every MIR4 and MIR5 source release. Retain historical scope and unique corrections without repeating reduced backport release logs. Do not invent release dates. The small formatter projects this Markdown into [source/changelog.txt](../source/changelog.txt), with native separators, indentation, unique version sections and valid continuation lines. All packaged release headings retain their source versions; a private same-edition build may project only its current source-version header without rewriting historical entries. Every distribution receives the same complete master history; its presence does not claim that a historical edition existed in an earlier MIR release. The [reconciliation inventory](inventory/changelog-history.json) preserves original input identities.

## Contributor builds and independently named forks

`TGT-08` — The maintainer's clarified 2026-10-26 direction requires an easy documented clone/edit/test/build/PR path, convenient private replacement builds, API extensions/companions, and honest guidance for independently maintained continuations. These are distinct use cases, not a ranked feature priority or a requirement to add a general fork platform. Use the existing build tools for private versions/metadata and the Lua-first SDK for API consumers. Keep official release identity/qualification controls strict. A private build receives no official release/support authority.

Distinguish same-name local replacement builds, independently named forks, and API consumers. The official default preserves all published prototype/setting/interface/migration identities and save behavior. Document the real local target/version commands and the ordinary upstream PR workflow; do not require private contributors to acquire release credentials or run unrelated native campaigns merely to create a local ZIP. Native/support claims still require their affected evidence.

Document the work a future renamed continuation would need: package-qualified imports/assets, shared prototype/settings/command/interface names, self-mod change detection, native ownership/overrides/contributions, migration scope and existing external consumers. Changing only info.json does not establish coexistence or save transfer. That identity/refactor exercise belongs to the continuation's author unless a concrete current consumer justifies an upstream change. Do not uproot current source, rename public identities or add a general namespace/build framework for this rare hypothetical. Factorio already isolates per-mod storage; [the storage contract](https://lua-api.factorio.com/latest/auxiliary/storage.html) is not a reason for another state layer.

Current compatibility must preserve unrelated foreign fields/state, reject unsafe writes before publication and avoid silent duplicate shared effects. Optional nonactivation requires a demonstrated safe path; missing established research is not an optional feature to drop. Keep the Generator local and deterministic, with no fork registry, recursive discovery or general runtime arbiter. Test the existing independent API consumers and actually admitted current-mod combinations. A future claimed renamed/coexisting build or save-transfer bridge requires its own explicit positive and affected save/client cases; do not imply arbitrary forks are already supported or automatically inherit MIR's research/migration history.
