---
title: "MIR Published Lines Development Copy Pack"
status: current
applies_to: "dev after the 2.4.9 publication return"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-20
supersedes: []
superseded_by: []
---

# MIR Published Lines Development Copy Pack

The `dev` branch is the consolidated development checkout for the completed publication campaigns through MIR 2.4.9. It contains the current Factorio 2.1 implementation, all portable fixes returned by the target lines, every published distribution, complete source snapshots for every published campaign line, the aggregate feature matrix, qualification evidence, tests, notes, changelog, and the current TODO.

The repository root remains the only active implementation. Historical source is intentionally stored under `.mir/target-lines/` so it can be copied or inspected without letting old Factorio APIs, metadata, settings, or feature cuts mutate the modern package.

## What To Copy Or Use

| Need | Authoritative path | Use |
| --- | --- | --- |
| Current mod code and data | repository root | Continue Factorio 2.1 development and build the current mod. |
| Exact published ZIPs | `dist/more-infinite-research_<version>.zip` | Install or redistribute the already-sealed release bytes. |
| Complete root distribution inventory | `.mir/distributions.json` | Verify every root ZIP by path, size, SHA-256, kind, and source ref. |
| Complete source for a published line | `.mir/target-lines/<version>/` | Copy target-specific code, data, tests, scripts, docs, notes, and evidence. |
| Snapshot identities | `.mir/target-lines/index.json` | Verify tag commit, Git tree, file count, byte count, and distribution hash. |
| Full release truth | `.mir/evidence/lower-wave/final-release-ledger.json` | Inspect source locks, binaries, qualification, seals, publication, and remaining gates. |
| 1.1 and 1.0 ring truth | `.mir/evidence/ring-1.1-1.0/final-release-ledger.json` | Inspect Factorio 1.1 and 1.0 qualification and publication. |
| Cross-target feature truth | `.mir/evidence/lower-wave/aggregate-feature-matrix.json` | Compare all 12 lower targets across 18 feature classes. |
| Evidence inventory | `.mir/evidence/lower-wave/aggregate-evidence-manifest.json` | Locate the 102 consolidated aggregate evidence entries and their identities. |
| Portable fixes and lessons | `.mir/portable-return.yml` | Reuse cross-version correctness, tooling, fixture, and target-profile lessons. |
| Release notes and synthesis | `docs/releases/` | Copy maintained release summaries, checklists, migrations, and decisions. |
| Player-facing history | `changelog.txt` | Use the consolidated Factorio-format changelog. |
| Current and historical work list | `todo.md` and `.mir/evidence/lower-wave/todo-2026-07-14-pre-consolidation.md` | Use current work truth or audit the pre-consolidation plan. |

Do not overlay an entire historical snapshot onto the repository root. Copy only the target-specific material you intend to study or reuse. The snapshot directories are runtime-inert development archives and must stay excluded from release ZIPs.

## Published Distributions And Source Snapshots

The tracked `dist/` directory contains 45 ZIPs: 44 immutable tagged releases plus the clearly classified MIR 3.2.0 development candidate. The exact machine-readable inventory is `.mir/distributions.json`; nonexistent or superseded 1.9.5, 2.4.1, and 2.5.0 candidates are not root distribution entries.

The complete tracked version inventory is 0.6.0, 0.7.0, 0.8.0, 0.9.0, 0.10.0, 0.11.0, 0.12.0; 1.0.0, 1.1.0, 1.1.5, 1.2.0, 1.2.5, 1.2.9, 1.3.0, 1.4.0, 1.5.0, 1.6.0, 1.7.0, 1.7.1, 1.8.0, 1.8.1, 1.8.2, 1.9.0, 1.9.1, 1.9.2, 1.9.3, 1.9.4; 2.0.0, 2.0.5, 2.1.0, 2.1.5, 2.2.0, 2.3.0, 2.3.5, 2.4.0, 2.4.5, 2.4.9; and 3.0.0, 3.0.5, 3.1.0, 3.1.1, 3.1.2, 3.1.5, 3.1.9, and the 3.2.0 development candidate.

Every row below is a final campaign version with both an exact ZIP in `dist/` and a complete tagged source tree in `.mir/target-lines/<version>/`.

| MIR | Factorio | Runtime proof | Tagged source commit | Distribution SHA-256 |
| --- | --- | --- | --- | --- |
| 3.1.9 | 2.1.10 | 102 of 102 scenarios | `1b9c6f32fc2bb53c413a593534e103a6043b4be3` | `D77B3A78DA40CD4FDD4C829A01B5030E59FB593F3387124EF5C438F6A9E8DFCD` |
| 2.4.9 | 2.0.77 | 106 machine checks and 92 runtime scenarios | `7ebe93029695bbf809a15a14c6540530738a9e62` | `B5503F94D04624F65462CC275FB6AA71A8CE93075F732DF498F6D73AD255F978` |
| 2.4.5 | 2.0 | 82 scenarios | `7e4b6c530cfcc5b2e1429c4e9f4ccb0d6d3b42a4` | `7649824B72247AA38F05661422DFDEE7C729B21CC73A0A35D2455443B45D39F8` |
| 1.9.4 | 1.1.110.62357 | 19 scenarios | `426d6d48c6578a786ea7de0f224282baff9d342b` | `74BA83E1F02FABBC52C09AC6144A409B243066663A6D132A47334459C2665BFB` |
| 1.8.2 | 1.0.0.54889 | 19 scenarios | `0a192c27674a6b13847e2f5e1b2b530e62419ee8` | `676927ECF801114CA8F7B9EFD6D139906432BCC60BE26B8CA5C08842E3686EFE` |
| 1.7.1 | 0.17.79 | 9 scenarios plus upgrade and reload | `9d9095c92055aebe557a55a7ab99bb9588fe73fb` | `2B2A395F014BF1C0C08596602A723E51F14199A9196B192858335FFE8ED9B25B` |
| 1.6.0 | 0.16.51 | 8 scenarios plus first-release reload | `a48509ed1dfbae8eba4b3dc7a701065063c12d5f` | `18EAE70A7FEE1FD50099D15985C4E5BE7DB018592EC3EFFC792950A920714544` |
| 1.5.0 | 0.15.40 | 4 scenarios plus first-release reload | `c2b526fd6dde81be7703daef53b075a1fd773e09` | `131162AA1A62C05E2C395C3F9D2495178742CD8C5324B058C42995C17F65B4DB` |
| 1.4.0 | 0.14.23 | 2 scenarios plus first-release reload | `fa192796ab274dd590c65b96d0f3f6a0f35cb155` | `69B7FC86E798937D44DF60E5E6DDC1FA636A10643B2E1BF54A79F5255CF984C1` |
| 1.3.0 | 0.13.20 | 2 scenarios plus first-release reload | `a33b99c1f39e1e779986a12a558a79ea97e69239` | `B07136627C913BA50C36B4F9453D972047F4FD3666BB9B8A79AB0EEFC9CA1749` |
| 0.12.0 | 0.12.35 | exact corrected archive first-release and reload | `82a349bd8137abe21145b321be4edb1e43e1e9e1` | `5171CD073A632AA30769FD9567F44AD2331BB5E7B852EC9F8576798398816612` |
| 0.11.0 | 0.11.22 | exact corrected archive first-release and reload | `679774c94bafdaa4d5432b793b8684ee4e43c257` | `38B9DFB72CE5EB0554CF2C9514D9B3D917B322DE5AC955A085A2A1BAADED2DEE` |
| 0.10.0 | 0.10.12 | exact corrected archive first-release and reload | `3377f835243c0cf9e7d2c2e76641c2c471341975` | `C2E42E9AE23E4A146F755B60D40009738724E7A0D3670D3B672D2068AE80912E` |
| 0.9.0 | 0.9.8 | exact corrected archive first-release and reload | `9325e744f1dd36baa33372dab6e7d9528ccfbab8` | `2114D67493C6B1076B1A71F27DC5197C8789C956570FD274507B8FD807C27D84` |
| 0.8.0 | 0.8.8 | exact corrected archive first-release and reload | `080fa92ea38b4b40156f26429bc7cba54948aef0` | `60BA156874CC3EE0C93B93C032BDEC6D8432B5F692009A3277C1890E6D9BF3E6` |
| 0.7.0 | 0.7.5 | exact corrected archive first-release and reload | `cb2991e3ea67b0413076c0e6d0dacf29d7f784b6` | `AA328AFF81F3133BAC3F432ADC7AF52CC49EFF43E40D04EAD99DCFBA92542749` |
| 0.6.0 | 0.6.4 | exact corrected archive first-release and reload | `12a5683c2aaed745f35e1261b437930a9a1476bc` | `0C53F30AFF4FCC3090323D3B319FAF6DD763D696983F60947BB07AB53617288A` |

The modern 102-scenario qualification used Factorio 2.1.10 with binary SHA-256 `DA4CA713FADBA1728904A2B47C2D73D2E07E8EB3AA2FAEED9AEE0FA6B417BAC3`. The 1.1 and 1.0 binary identities are recorded in the ring ledger and its synthesis document. Lower-wave exact binary identities are recorded per release in the final lower-wave ledger.

## Consolidated Features, Fixes, And Refactoring

The active root contains the portable implementation outcomes from the entire campaign:

- Capability-driven target profiles and runtime adapters replace version-string branching for scenario selection, CLI behavior, logs, markers, settings fixtures, package deployment, and save addressing.
- Iterative deterministic technology-graph traversal avoids Lua recursion exhaustion while retaining stable cycle identities and the narrow Muluna Astroponics repair.
- Generated count formulas use compact whitespace-free syntax across modern and historical parsers without changing their mathematical curves.
- Candidate identity normalizes text line endings, binds source and scenario manifests, and directly proves the exact frozen distribution instead of accepting content similarity alone.
- Museum metadata generation now emits and validates an explicit target-matching `factorio_version`, preventing validator-only failures from escaping deterministic runtime qualification.
- Compilation plans are published only after authoritative validation accepts them; selected configuration-change checks execute both real load phases.
- Validation fixtures derive science, recycler, streams, settings, and metadata from positive target capabilities instead of assuming Factorio 2.1 shapes.
- Retention runners own Factorio process lifecycles through timeout, wait, and process-tree termination, leaving no surviving validation processes.
- Historical runners use declared target capabilities for benchmark flags, authoritative log sources, recoverable diagnostics, loaded-map grammar, audio flags, exit markers, extracted-package deployment, and 0.13 save staging.
- Deterministic packagers preserve immutable release bytes and reject development-only paths such as `.mir`, docs, scripts, tests, fixtures, and `dist` from the mod ZIP.
- Compatibility policy remains declarative: only emission code creates or mutates generated technology prototypes, and every generated technology retains a stable stream-manifest row.

The aggregate feature matrix covers 12 lower targets by 18 feature classes, or 216 explicit cells, with no blanks. Cells state `native`, `adapted`, or an evidence-backed omission rather than implying unsupported parity.

## Portable Lessons Returned To Dev

The full records, source commits, fixtures, decisions, and replayed target commits are in `.mir/portable-return.yml`.

| Lesson | Durable result |
| --- | --- |
| PL-001 | Replayed the released settings and recycler contract through the Factorio 2.0 profile while keeping modern 3.0.5 behavior authoritative. |
| PL-002 | Preserved the immutable recycling index and build-once classifier boundary across 2.1 and 2.0. |
| PL-003 | Made runtime scenario declarations target-explicit and completeness-checked before execution. |
| PL-004 | Made candidate fingerprints invariant to checkout line endings. |
| PL-005 | Required direct loading and proof of the exact frozen distribution for release qualification. |
| PL-006 | Kept Factorio 2.0 dependency and cargo feature cuts target-local. |
| PL-007 | Replaced hard-coded version dispatch with positive target capabilities. |
| PL-008 | Made cross-version fixtures derive assertions from target capabilities. |
| PL-009 | Parameterized upgrade identities instead of encoding a single release pair. |
| PL-010 | Emitted compact generated formulas accepted by historical parsers. |
| PL-011 | Declared ordered target-specific weapon prerequisite candidates and selected the first valid researchable chain. |
| PL-012 | Replaced recursive technology traversal with an iterative deterministic walk. |
| PL-013 | Published only validated accepted compilation plans. |
| PL-014 | Routed configuration-change declarations through the actual two-phase executor. |
| PL-015 | Generated settings-override fixture metadata from the selected target profile. |
| PL-016 | Declared ancient-engine CLI and settings support as target-owned validation capabilities. |
| PL-017 | Added explicit ownership, timeout, waiting, and termination for retention processes. |
| PL-018 | Added capability adapters for logs, diagnostics, map markers, audio flags, exit markers, benchmark behavior, and save addressing. |

## Changelog, TODO, Notes, And Evidence

`changelog.txt` has a source-faithful section for every published line and the active 3.2.0 development candidate. `todo.md` records completed consolidation and only the remaining manual, portal, reliability, and future-development gates. The exact earlier TODO is retained as lower-wave evidence so no plan or note was lost during cleanup.

The release synthesis documents explain decisions and limitations rather than duplicating raw ledgers:

- `docs/releases/3.1.9-post-2.4.5-ring-synthesis.md`
- `docs/releases/lower-wave-0.17-to-0.6-synthesis.md`
- `.mir/evidence/ring-1.1-1.0/final-release-ledger.json`
- `.mir/evidence/lower-wave/final-release-ledger.json`
- `.mir/evidence/lower-wave/post-publication-dev-requalification.json`

## Remaining Gates

- Factorio Mod Portal publication for 1.9.4, 1.8.2, and 1.7.1 through 1.3.0 remains blocked until `MOD_UPLOAD_API_KEY` is available.
- Maintainer manual gameplay and balance review remains pending where the release ledgers say `PENDING-MAINTAINER`; automated results do not claim that review was performed.
- Mod Portal upload and acceptance for the metadata-corrected 0.12.0 through 0.6.0 archives remain maintainer actions; GitHub publication and exact-binary proof do not claim portal acceptance.
- No Factorio 0.5 campaign, retag, force-push, or rewrite of a published archive is authorized by this consolidation. MIR 3.2 implementation continues under its current governed development plan.

## Validation Boundary

The source snapshots are complete tag exports, but they are not active validator inputs. Static validation deliberately excludes `.mir/target-lines/` from modern package asset ownership checks while continuing to enforce the active root. Snapshot integrity is separately proved by comparing each staged snapshot Git tree to its published tag root tree, hashing all 45 tracked root archives against `.mir/distributions.json`, and binding the 17 final campaign archives to `.mir/target-lines/index.json`.

The 2026-07-15 consolidation gate passed Markdown formatting, docs and governance manifests, architecture boundaries, settings visibility, locale checks, all 78 active PowerShell scripts, scenario manifests, deterministic planner tools, schema and contract coverage, package identity invariance, policy and claim lints, the 70 stable plus 2 predeclared golden identities, changelog format, package construction, and forbidden-entry hygiene. Two independent builds produced development-package SHA-256 `7105D01F3C0847FD6641728BDDE93FA90DC8D723945B89C7E30AB051109B50F5`.

The 2026-07-16 museum metadata correction gate again passed docs, architecture, the complete static suite, all seven deterministic museum builds, 26 museum negative cases, 16 staged source-snapshot identities, and all 46 root distribution hashes. The refreshed development-package builds were byte-identical with SHA-256 `3DBCCE7903FB6182D34C83E67E2DDF277E0BB8B8FD8042C2C238A1F78BB1129D`.

The current machine does not contain the Factorio 2.1 executable, so the 102-scenario runtime catalog was not rerun against the changelog-updated development package. The immutable released 3.1.9 ZIP remains bound to its accepted 102-of-102 runtime evidence and SHA-256 `D77B3A78DA40CD4FDD4C829A01B5030E59FB593F3387124EF5C438F6A9E8DFCD`; that historical proof is not represented as a new exact-package run.
