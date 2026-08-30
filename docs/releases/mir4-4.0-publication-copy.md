---
title: "MIR 4.0 Publication Copy"
status: current
applies_to: "MIR 4.0.0 candidate programme"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-29
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-4.0-github-release-copy
  - mir4-4.0-mod-portal-copy
  - mir4-4.0-player-faq
  - mir4-4.0-target-changelog-copy
  - mir4-4.0-release-announcement
---

# MIR 4.0 Publication Copy

This is prepared copy, not publication authority. T19 must replace or confirm every bracketed field from the exact frozen records; T20 must confirm rebuilt bytes; T21 must bind sealed and publicly read-back bytes before this copy may describe a completed release.

## Fixed names

- GitHub release title: `More Infinite Research 4.0.0 — Whole-Platform Genesis`
- Announcement title: `MIR 4.0.0 released: one source, four Factorio target builds`
- Mod Portal short description: `Configurable, compatibility-aware productivity and bonus research for Factorio, with target-specific builds, safe ownership, explicit omissions, and upgrade-preserving migrations.`

## Current pre-freeze candidate facts

These are verified local, publication-forbidden candidate facts as of 2026-08-29. They are not a seal or a promise that the final release will retain the same bytes.

| Target | Distribution | Direct predecessor | Pre-freeze ZIP SHA-256 | Content root | Current exact engine |
| --- | --- | --- | --- | --- | --- |
| F210 | `4.0.21000` | `3.2.11` | `38541A7ED0A4181811A1E94231FF58A1268F91E7B89C7CA3D9D5F682242094B1` | `CA72A8045654FFDC8630D54567F6D04A1B40BA5682ED06E7FACCF2772A2660ED` | Factorio 2.1.17 build 87315, Steam build 24955935, executable `710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8` |
| F200 | `4.0.20000` | `2.5.11` | `5C0E299D78C4EE545958448DAE48D87BE5FE1B959875D4CB93A264D95D3DB0AE` | `5163E45530CB9B4DAEAC27166279809933750C605BA6E3EC785A0267B9428A1F` | Factorio 2.0.77 build 84539, executable `D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B` |
| F110 | `4.0.11000` | `1.9.9` | `BE63F76255068BAC1BA891B9C9331E4EA943538A37808DFF546E5B1A3ECEB62D` | `B3DAA35E6E72741D8054C4EC22435CC8216CB6A5E2566D10CF9E3B934E3FF682` | Factorio 1.1.110 build 62357, executable `B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1` |
| F100 | `4.0.10000` | `1.8.9` | `EA495B37C0B91F0728226290CDAEFDF4BBD3C1DBA7D0997AAF5E5107FE79AD3F` | `1ABDA788DE4B287A48AB0B8787C8F7826256E4ECAB7085C3A6FDDD1E9DF145B2` | Factorio 1.0.0 build 54889, executable `99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70` |

## GitHub release body

### More Infinite Research 4.0.0 — Whole-Platform Genesis

MIR 4.0.0 begins the permanent More Infinite Research 4 product line. One source release produces independently generated and qualified packages for supported Factorio lines. Install only the package matching the game version; the encoded distribution number identifies the target and shared source patch.

### Player packages

| Package | Factorio | Upgrade from | Qualification |
| --- | --- | --- | --- |
| `more-infinite-research_4.0.21000.zip` | 2.1 | MIR 3.2.11 | Qualified on Factorio `[F210_FREEZE_VERSION]` build `[F210_FREEZE_BUILD]`; SHA-256 `[F210_FREEZE_ENGINE_SHA256]` |
| `more-infinite-research_4.0.20000.zip` | 2.0 | MIR 2.5.11 | Qualified on Factorio 2.0.77; SHA-256 `D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B` |
| `more-infinite-research_4.0.11000.zip` | 1.1 | MIR 1.9.9 | Reduced LTS target qualified on Factorio 1.1.110; SHA-256 `B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1` |
| `more-infinite-research_4.0.10000.zip` | 1.0 | MIR 1.8.9 | Reduced LTS target qualified on Factorio 1.0.0; SHA-256 `99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70` |

Package checksums and signatures are in `[CHECKSUM_FILE]`. Every published package and asset was redownloaded and compared with the sealed release bytes under `[PUBLIC_READBACK_RECEIPT]`.

### What changed

- Established one MIR `4.0.0` source release with target-coded Factorio distributions.
- Preserved the proven player compiler, emitter, technology IDs, settings, migrations, runtime state, and direct upgrade paths while moving target construction, assurance, and release operations behind governed MIR 4 contracts.
- Retained configurable productivity and bonus research across intermediates, science, infrastructure, logistics, combat, player bonuses, robots, and supported Space Age systems.
- Preserved valid external technology ownership and rejected duplicate or unsafe research effects with explicit diagnostics.
- Kept maximum-level enforcement, research progress, current research, queue state, science routes, and migrations target-aware.
- Added exact environment locks, compatibility diagnostics, support bundles, deterministic target packaging, supply-chain records, offline reconstruction, and public-byte verification.
- Added separate MIR 4 API/SDK, MEP, reference-extension, and Inspector developer-preview assets.

### Stable, preview, and shadow boundaries

Player packages use the release-qualified stable compiler, emitter, runtime, migrations, and target behavior. Separately downloaded developer previews provide versioned schemas, APIs, language bindings, extension tooling, examples, conformance tests, environment/support tools, and the read-only Inspector; they are not Factorio mods. Executable shadow architecture in the repository can normalize, compile, inspect, and diagnose, but cannot mutate player packages or create public support claims.

### Compatibility

MIR supports vanilla, official content, and exact evidence-backed mod environments. Compatibility is not a blanket claim over every modpack. MIR applies certified behavior, preserves valid external owners, omits unsupported target surfaces, or reports the exact extension or review required. See `[COMPATIBILITY_CLAIMS_LINK]` for the claims and limitations sealed with this release.

### Factorio 2.1 experimental policy

While Factorio 2.1 remains experimental, F210 qualification follows the installed official Steam experimental at or above the unchanged `2.1.8` compatibility floor and binds its exact version, build, file version, executable, Steam build, and manifest for each execution. T19 freezes one exact identity; any drift invalidates the candidate and requires rebuild and full F210 requalification. The pre-freeze engine observed on 2026-08-29 was Factorio 2.1.17 build 87315, but the public release statement must name the exact T19 frozen engine: `[F210_FREEZE_VERSION]` build `[F210_FREEZE_BUILD]`, executable SHA-256 `[F210_FREEZE_ENGINE_SHA256]`.

After Factorio 2.1 becomes stable and an append-only transition authority is accepted, F210 qualification uses exact stable-minimum 2.1.8 and latest-stable 2.1.x lanes. A newer qualification engine never silently raises the package compatibility floor.

### F110 and F100

The Factorio 1.1 and 1.0 packages are reduced LTS targets. They omit effects, settings, transports, runtime handlers, and presentation surfaces their engines cannot safely represent. They are independently built and tested; they do not claim feature parity with F210 or F200.

### Upgrading

1. Back up the save and current mod directory.
2. Install the package matching the Factorio line and remove the predecessor ZIP.
3. Keep startup settings unchanged for the first load.
4. Load from the direct predecessor listed above.
5. Save after the migration/configuration-change pass, then reload the upgraded save twice.

Detailed guidance: `[UPGRADE_GUIDE_LINK]`.

### Developer preview assets

- `mir4-api-sdk-v1-preview.zip`
- `mir4-mep-v1-preview.zip`
- `mir4-reference-extension-v1-preview.zip`
- `mir4-inspector-v1-preview.zip`

These package-excluded development tools do not grant player mutation authority or an automatic compatibility claim.

### Verification and preservation

- Source commit: `[SOURCE_COMMIT]`
- Source tree: `[SOURCE_TREE]`
- Release candidate: `[CANDIDATE]`
- Package-source SHA-256: `[PACKAGE_SOURCE_SHA256]`
- Proof root: `[PROOF_ROOT]`
- Seal root: `[SEAL_ROOT]`
- Signer fingerprint: `[SIGNER_FINGERPRINT]`
- Offline restore receipt: `[RESTORE_RECEIPT]`

The release includes deterministic manifests, component inventories, SBOMs, provenance, signatures, qualification summaries, an offline restoration receipt, and public-byte verification receipts.

### Known limitations

- Factorio 2.1 remains experimental until the official stable transition is separately admitted.
- Target builds have explicit capability differences.
- Developer API/MEP/SDK V1 remains a preview rather than a frozen long-term 1.0 contract.
- Complex or opaque scripted mod semantics may be preserved, extension-required, review-required, or omitted instead of automatically modified.
- Only compatibility claims backed by exact current evidence are qualified.

## Mod Portal information page

### More Infinite Research

*Trickle-down economics bring productivity gains to all industries.*

More Infinite Research adds configurable productivity and bonus research for intermediates, science packs, infrastructure, logistics, combat, player bonuses, robots, and supported Space Age systems.

MIR discovers the active technology, recipe, item, fluid, science-pack, and laboratory environment late in the prototype stage. It creates or adopts research only when ownership, target capability, progression, and safety checks permit it. Unsupported or ambiguous subjects are preserved, omitted, or reported instead of being forced into an invalid technology tree.

### Choose the correct download

| Factorio line | Package pattern | MIR 4.0 package |
| --- | --- | --- |
| 2.1 | `4.MINOR.210PP` | `4.0.21000` |
| 2.0 | `4.MINOR.200PP` | `4.0.20000` |
| 1.1 | `4.MINOR.110PP` | `4.0.11000` |
| 1.0 | `4.MINOR.100PP` | `4.0.10000` |

`PP` is the shared source patch. Distribution versions from different targets are not a simple higher-is-newer sequence; select the package matching the running Factorio line.

### Main features

- Configurable recipe and fluid productivity research.
- Infinite or bounded continuations for supported technologies.
- Direct bonuses for logistics, weapons, robots, laboratory research, player attributes, and Space Age cargo systems where supported.
- Per-family enablement, cost, growth, maximum level, research time, effect scaling, science policy, and compatibility controls.
- Target-aware science-pack and laboratory reachability.
- Stable generated technology identities and upgrade-preserving migrations.
- Safe external-owner adoption and duplicate-effect prevention.
- Explicit diagnostics for skipped, preserved, conflicting, or unsupported behavior.

F210 and F200 are the full maintained targets where features are representable. F110 and F100 are reduced LTS targets with explicit omissions. Compatibility is qualified against exact Factorio versions, mod archives, settings, load order, and evidence; MIR does not claim automatic perfection for every arbitrary modpack.

Report problems with the Factorio version, MIR target package, exact mod list and startup settings, `factorio-current.log`, a save or minimal reproducer, and the MIR support bundle when available. Never include passwords, API tokens, signing material, or unrelated private files.

Developer previews are separate GitHub downloads, not installable player mods.

## Mod Portal FAQ

### Which MIR version should I install?

Use Factorio 2.1 → `4.0.21000`, Factorio 2.0 → `4.0.20000`, Factorio 1.1 → `4.0.11000`, or Factorio 1.0 → `4.0.10000`. Never install an API, SDK, MEP, reference-extension, or Inspector preview archive as a Factorio mod.

### What do MIR 4 version numbers mean?

MIR has a shared source version and a target distribution version. For source `4.6.8`, the target packages are `4.6.21008`, `4.6.20008`, `4.6.11008`, and `4.6.10008`. Compare source versions within one target; a package for another target is not newer merely because an encoded component is numerically larger.

### Does MIR support every mod or modpack?

No blanket claim is made. MIR provides structural compatibility and exact evidence-backed profiles, but does not guess arbitrary hidden Lua behavior. It can apply certified behavior, preserve an existing owner, request an extension or review, omit an unsupported target surface, or report a hard-safety failure.

### Why was a technology skipped or preserved?

Typical reasons include another valid owner, an unavailable target effect, unreachable science, a missing or cyclic prerequisite, a recycling/recovery process family, or custom semantics requiring an extension or review. Check MIR diagnostics or export a support bundle.

### Can I change costs, effects, or maximum levels?

Yes. MIR exposes target-appropriate startup settings for research families, costs, growth, time, effect scaling, science policy, and maximum levels. Unsupported settings are omitted or hidden on reduced targets rather than presented as inert controls.

### Can mod developers add first-party MIR support?

Yes. The separate developer preview includes the data-only MIR Extension Protocol, schemas, templates, SDK bindings, environment locks, diagnostics, and conformance tools. Extensions cannot bypass hard safety or mutate player prototypes directly.

### How do I report an issue?

Open a Mod Portal discussion or GitHub issue with the Factorio version, MIR package version, mod list, startup settings, log, support bundle, and smallest available reproducer.

## Target changelog source

The package generator must render this semantic source into Factorio changelog format and replace the heading with the target distribution version.

### Common changes

- Began the MIR 4 Whole-Platform Genesis line with one canonical source release and independently generated target distributions.
- Added target-coded identities for Factorio 2.1, 2.0, 1.1, and 1.0 while preserving stable technology, setting, migration, and runtime-state identities where supported.
- Preserved the proven player compiler and emitter while moving target construction, release operations, developer APIs, extensions, ProcessIR, Inspector, and assurance behind explicit maturity boundaries.
- Added deterministic target packaging, exact environment locks, diagnostics, support bundles, supply-chain records, offline restoration, signatures, and public-byte verification.

### Common compatibility and migration

- Preserved direct upgrades from MIR 3.2.11 on Factorio 2.1, MIR 2.5.11 on Factorio 2.0, MIR 1.9.9 on Factorio 1.1, and MIR 1.8.9 on Factorio 1.0 for independently admitted targets.
- Preserved valid native and external research owners, rejected duplicate effects, and retained target-local science, laboratory, prerequisite, process-safety, and maximum-level validation.
- Retained existing MIR technology IDs, settings, fractional research progress, queue state, and governed runtime namespaces through the direct predecessor path.
- Made unsupported target features explicit omissions rather than inert or invalid package content.

### F210 target supplement

- `Version: 4.0.21000`
- Targets Factorio 2.1 with package compatibility floor 2.1.8.
- Qualified against experimental Factorio `[F210_FREEZE_VERSION]` build `[F210_FREEZE_BUILD]`, executable SHA-256 `[F210_FREEZE_ENGINE_SHA256]`.

### F200 target supplement

- `Version: 4.0.20000`
- Independently qualified on Factorio 2.0.77.
- Omits Factorio 2.1-only effects, prototypes, transports, settings, and runtime handlers.

### F110 target supplement

- `Version: 4.0.11000`
- Provides the independently generated reduced LTS subset for Factorio 1.1.
- Omits recipe-productivity and newer Factorio 2.x/DLC surfaces the engine cannot safely represent.

### F100 target supplement

- `Version: 4.0.10000`
- Provides the independently generated reduced LTS subset for Factorio 1.0.
- Uses target-era runtime, technology, locale, icon, and migration representations and does not claim Factorio 2.x feature parity.

## Post-release announcement

More Infinite Research 4.0.0 — Whole-Platform Genesis is now available. MIR now uses one source release with independently generated packages for Factorio 2.1, 2.0, 1.1, and 1.0. Existing technology IDs and direct upgrade paths are preserved while target differences and unsupported features are explicit. Separate developer previews provide the MIR 4 API/SDK, Extension Protocol, reference extension, and read-only Inspector; they are not player mods. Choose the package matching the Factorio line and consult the release notes for exact engine qualification, checksums, migration instructions, and known limitations.

## Finalization checks

Before publication, the release manager must prove that no bracketed field remains, every target row is admitted, each package checksum equals the frozen reconstruction and seal, the F210 statement names the exact frozen version/build/date, links resolve to immutable records, deferred targets are absent from downloadable-product claims, and redownloaded public bytes equal the seal. Publication failure leaves exact sealed bytes in `publication-pending`; it never authorizes a rebuild.
