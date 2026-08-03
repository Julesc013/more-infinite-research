---
title: "MIR Extension Protocol v1 Roadmap"
status: current
applies_to: "3.3.x, 2.6.x"
audience: developer
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-04
supersedes: []
superseded_by: []
---

# MIR Extension Protocol v1 Roadmap

MIR 3.3 and 2.6 must be extendable by installing another mod, not only by editing MIR. MEP-1 is a host-neutral, capability-negotiated, data-first protocol for compatibility, profiles, tuning, declarative providers, proof, presentation, bounded runtime descriptors, and separately governed advanced adapters.

The protocol is a first-class release objective, not a convenience API added after the compiler refactor. Ordinary compatibility must be possible without MIR source changes, private compiler imports, central services, or permission from the official project.

This document plans the protocol. It does not declare a currently implemented public API, qualify a third-party pack, or authorize an extension to mutate prototypes.

## Product outcomes

MEP-1 must support all of these paths:

1. A player generates a useful local compatibility or tuning mod without writing Lua.
2. A mod author embeds data-only MIR support in their own mod without importing private compiler code.
3. A third party publishes a standalone compatibility mod that compatible hosts discover automatically.
4. Multiple independent extensions compose deterministically and produce actionable conflicts.
5. A compatible community fork consumes the same declarative extensions under a different repository, maintainer, or package name.
6. No extension bypasses MIR hard safety, prototype-mutation ownership, claim governance, or proof requirements.
7. Extension changes participate in semantic impact, evidence reuse, target projection, diagnostics, migration, and release qualification.
8. Startup and runtime require no MIR server, central registry, online signature service, GitHub API, or Mod Portal lookup.

## Protocol identity and release allocation

The canonical machine identifier is planned as:

```text
more-infinite-research.extension.v1
```

Protocol and product versions are independent:

```text
MIR release                 3.3.x / 2.6.x
Extension protocol          1.x
Compatibility fragment      independently versioned
Profile fragment            independently versioned
Declarative provider        independently versioned
Runtime descriptor          independently versioned
Evidence ABI                Control Plane owned
```

MIR 3.3.0 establishes the stable declarative protocol, automatic discovery, legacy adapter, compatibility and profile fragments, capability negotiation, sealed safety, deterministic conflicts, inventory, CLI SDK, examples, and fork-continuity conformance. MIR 3.3.1 adds the offline non-programmer builder and migration/diagnostic UX. MIR 3.3.2 adds declarative family-provider composition and may introduce experimental trusted adapters. MIR 2.6.0 projects the same MEP-1 semantics through Factorio 2.0 transports and qualifies them independently.

## Reuse current architecture

The existing compatibility-pack system already provides the correct starting principles: data-only records, schema validation, target and version applicability, exact evidence for reviewed risk refinements and generation authorizations, deterministic sorting, one policy-authority facade, and a hard-safety boundary that pack data cannot override.

The current limitations are:

- One fixed singleton `mod-data` prototype requires unrelated extensions to coordinate writes.
- The provider registry admits only built-ins.
- The provider contract is too broad for an author who owns one focused surface.
- One linear precedence rank cannot express every field-specific merge law.
- Factorio 2.1 and 2.0 have different transport capabilities.

MEP-1 evolves these authorities. It does not create a second compatibility compiler.

## Separate semantics from transport

```text
Extension semantic envelope
        ↓
one or more target transports
        ↓
canonical frozen ExtensionRegistry
        ↓
existing compatibility, policy, provider, compiler, report, and proof authorities
```

An extension's canonical identity comes from its validated manifest, not its prototype name, registration order, transport, source repository, or official-host package name.

### Factorio 2.1 unique `mod-data`

Factorio documents `mod-data` as arbitrary prototype-stage data whose `data_type` may identify compatibility data expected to be discovered by another mod. Each extension should therefore emit its own uniquely named prototype rather than mutate a shared singleton:

```lua
data:extend({
  {
    type = "mod-data",
    name = "example-mod--mir-extension--belt-support",
    data_type = "more-infinite-research.extension.v1",
    data = extension_manifest,
  },
})
```

The 2.1 collector scans every `mod-data` prototype with the MEP-1 data type, then validates and normalizes its payload. The prototype name is only transport provenance.

Official Factorio API reference: [ModData](https://lua-api.factorio.com/latest/prototypes/ModData.html).

### Portable stage-local bus

The repository target profile records `mod_data = false` for Factorio 2.0. MEP-1 therefore also needs a small namespaced stage-local registration bus usable on both 2.0 and 2.1:

```lua
local key = "__MIR_EXTENSION_PROTOCOL_V1__"
local bus = rawget(_G, key)

if bus == nil then
  bus = { schema = 1, contributions = {} }
  rawset(_G, key, bus)
end

assert(bus.schema == 1, "Incompatible MIR extension bus")
bus.contributions["example-author.example-mod.belts"] = extension_manifest
```

Factorio documents one shared Lua state for each settings or prototype stage, ordered base/update/final-fixes rounds, and disposal of that state at stage completion. That makes an ephemeral declaration bus architecturally plausible. MEP-1 must still prove exact behavior on both supported targets, including declarations before and after the host base file, host absence, registry freeze, duplicate transport delivery, and a different host package name.

Official Factorio API reference: [Data lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html).

### Host registration module

An intentionally host-bound bridge may use a public stable wrapper:

```lua
local mir = require("__more-infinite-research__/api/data_stage_v1")
mir.register_extension(extension_manifest)
```

The wrapper publishes to the same canonical transport layer. It is a convenience API, not the semantic protocol, because it depends on one internal mod name.

### Generated static integration

Reduced targets may consume a deterministic generated static manifest when they cannot implement either dynamic transport. Static integration remains a target projection of the same semantic record.

## Host-absence behavior

An ordinary standalone extension should depend on the target mod or modpack it supports, publish its declaration unconditionally, remain inert when no compatible host is active, and activate automatically when a compatible host is later installed.

It must not import private MIR modules, create gameplay content merely to advertise compatibility, require the official GitHub repository, or fail startup because no MIR-compatible host is present.

## Extension envelope

The canonical envelope aggregates independently versioned fragments:

```yaml
schema: 1
record_type: MirExtensionEnvelope

protocol:
  name: more-infinite-research.extension
  major: 1
  minor: 0

identity:
  id: example-author.example-mod.belts
  version: 1.2.0
  namespace: example-author.example-mod

source:
  mod: example-mir-compat
  expected_version: ">= 1.2.0"

host:
  required_protocol: ">= 1.0, < 2.0"
  requires_all:
    - compatibility-pack.v3
    - profile-fragment.v1
  optional:
    - provider-declarative.v1

targets:
  factorio_lines: ["2.1", "2.0"]

applicability:
  mods_all:
    - id: example-mod
      version: ">= 4.0.0, < 5.0.0"
  mods_none: []

dependencies:
  extensions: []

conflicts:
  extensions: []

fragments:
  compatibility:
    - ref: compatibility/example-belts@1
  profiles:
    - ref: profiles/example-balanced@1
  proofs:
    - ref: proofs/example-belts@1

budgets:
  maximum_fragments: 32
  maximum_claims: 256
  maximum_selectors: 256
  maximum_operations: 512
  maximum_diagnostic_bytes: 65536

claim:
  source_class: community
  public: false
  maturity: unverified
```

Each fragment has its own schema, owner, version, semantic identity, authority identity, target disposition, and proof contract. A documentation or profile edit must not invalidate an unchanged compatibility selector.

## Stable declarative surfaces

### Compatibility fragment

Compatibility fragments evolve the current `CompatibilityPack`: aliases, exact includes and excludes, bounded family hints, science roles, owner claims, reviewed risk refinements, candidate seeds, family authorizations, target applicability, evidence references, and claim metadata. Exact selectors and evidence remain mandatory wherever current hard-safety rules require them.

### Profile and tuning fragment

Profiles may select safe feature enablement, safe owners, science and prerequisite policy, cost/effect values within bounds, maximum-level preferences, MIR-owned presentation, and target recommendations. Profiles cannot widen hard safety.

### Declarative family-provider fragment

A provider composes registered bounded operators for discovery, normalization, classification, risk, science, prerequisites, ownership, and balance. Ordinary providers cannot execute arbitrary callbacks.

```yaml
id: example-provider.belt-machines
family: belt-machine-manufacturing
pipeline:
  discover: recipes.output-place-result
  normalize: recipe-item-entity
  classify: entity.belt-family
  risk: productivity-safe-placeable
  science: inherit-target-stream
  prerequisite: inherit-target-stream
  owner: preserve-exact-owner
  balance: productivity-standard
```

New family creation remains review-gated until its operator set, complexity, target behavior, and property corpus are qualified.

### Static settings contribution

An extension may add a genuinely necessary namespaced startup setting only during the settings stage. Most extensions should use sparse profile fields instead. A final recipe or technology discovered during the prototype stage cannot retroactively create a startup setting.

### Presentation fragment

Presentation fragments may provide locale, descriptions, ordering hints, extension-owned icons, and presentation for MIR-created extension content. They cannot globally change unrelated external technologies.

### Proof fragment

Proof fragments declare positive and negative fixtures, expected dispositions, exact environment envelopes, claim dimensions, limitations, and proof requirements. They request evaluation; they do not confer official claim maturity.

### Runtime descriptor

MEP-1 runtime descriptors initially reference only MIR-provided bounded handler operators. They declare state namespace and schema, event subscriptions, filters, migration references, target requirements, determinism, and complexity. Arbitrary runtime callbacks are not part of the stable declarative protocol.

## Registry lifecycle

### Settings stage

```text
static SettingContributions
→ validate and normalize in SettingsRegistry
→ freeze during settings-final-fixes
→ emit setting prototypes
```

### Prototype stage

```text
collect unique mod-data, stage-bus, host-module, and legacy singleton inputs
→ copy untrusted values
→ validate schema, namespace, source, applicability, capabilities, and budgets
→ canonicalize and fingerprint
→ deduplicate identical multi-transport contributions
→ resolve dependencies and conflicts
→ freeze ExtensionRegistry
→ publish accepted and quarantined inventories
→ compose existing policy and provider authorities
→ compile
```

Registration order never becomes policy precedence. Late mutation after registry freeze fails with a stable diagnostic.

### Runtime stage

The host may expose read-only active-feature, accepted-extension, profile, claim, diagnostics, state-schema, and support-export surfaces. Third-party runtime mods normally retain their own event handlers and state.

## Hard safety and allowed policy

Extensions cannot override missing targets, unsupported effects, invalid shapes, duplicate effective owners, unreachable technology graphs, science/lab impossibility, proven unsafe economy loops, migration identity failures, target capability exclusions, operation budgets, or mutation ownership.

Always-safe restrictive requests include disabling a feature, excluding a recipe, reducing scope, requesting diagnostic-only behavior, selecting a stricter cap, and suppressing MIR-owned presentation.

Legal policy preferences select among already safe alternatives: owner, science, prerequisite, cost, effect scale, maximum level, create versus preserve, and preview versus apply.

Reviewed risk refinements require an exact selector, exact target-mod version envelope, named evidence, a reviewable risk class, and a bounded action. Stable MEP-1 has no hard-safety bypass.

## Field-specific conflict resolution

| Field | Merge behavior |
| --- | --- |
| Hard safety | Deny dominates. |
| Feature disable | Most restrictive wins. |
| Target capability | Intersection. |
| Owner | Exclusive arbitration. |
| Science packs | Explicit union, intersection, or replace. |
| Prerequisites | Graph merge followed by cycle and reachability proof. |
| Numeric tuning | Declared replace, minimum, maximum, multiply, or clamp. |
| Presentation | Most specific legal presentation owner. |
| Diagnostics | Append and deduplicate. |
| Evidence | Immutable union. |
| Extension dependencies | Directed graph resolution. |
| Runtime subscriptions | Deterministically sorted set. |

Every merge operator declares whether it is associative, commutative, idempotent, or ordered, and property tests prove the declaration.

Source authority classes include core safety, target capability, core reviewed, extension reviewed, community, modpack profile, user local, generic default, and heuristic. Source class alone cannot resolve every field; subject specificity, version envelope, and the registered merge law also apply.

A conflict report names the subject, field, both sources and requested values, merge law, reason automatic resolution failed, safe choices, and the local profile or resolution-pack field that can select a winner.

## Advanced trusted adapters

`TrustedAdapterV1` is a separate experimental escape hatch for genuinely new discovery, normalization, classification, policy, presentation, or target adaptation.

An adapter receives an immutable snapshot, returns data-only records, declares semantic reads and complexity, has no raw `CompilerContext`, executor, or SafetyKernel access, cannot mutate prototypes through MIR, cannot confer official claim status, is exact-archive-bound in release evidence, and is quarantined when its ABI is unavailable.

The contract preserves MIR architecture and proof boundaries. It is not a security sandbox around another Factorio mod's Lua execution.

Promotion is explicit:

```text
experimental trusted adapter
→ community qualified
→ reviewed adapter
→ optional promotion into the bounded core operator registry
```

## Finalizer-order contracts

Declaration discovery cannot solve a target mod that mutates relevant prototypes after MIR's compiler pass. An extension may declare a required relation such as host-after-target-final-fixes, but the host dependency graph must make that relation satisfiable.

When the relation is not satisfied, the affected fragment remains diagnostic or review-required. A bridge or fork may add the required dependency edge and then qualify the exact environment. MEP-1 must never pretend a compatibility pack can rewrite the host package's dependency metadata from inside the data stage.

## Player workflow

The target beginner workflow is:

1. Export a privacy-safe support bundle containing exact environment identity, unresolved subjects, candidates, owners, science/lab facts, risks, current profile, capabilities, and safe actions.
2. Open an offline CLI wizard or self-contained local web builder.
3. Choose Basic, Advanced, or Expert mode.
4. Preview requested policy, predicted outcome, safety results, conflicts, and target portability against the exported semantic snapshot.
5. Generate a standalone mod ZIP, source manifest, locale, README, and optional fixture template.
6. Install the ZIP and inspect whether it was accepted, partially accepted, quarantined, conflicted, or unsupported.

The builder requires no account, server, or network connection. Basic mode offers bounded choices such as ignore, normal manufacturing, attach to an existing technology, create when qualified, preserve the external owner, or disable the MIR feature.

## Mod-author and contributor workflow

Planned commands are:

```text
mir extension scaffold
mir extension validate
mir extension test --snapshot
mir extension test --factorio --target 2.1
mir extension test --factorio --target 2.0
mir extension explain
mir extension package --target
mir extension migrate --from --to
mir extension doctor
```

Every major command supports structured output, explanation, dry run, and explicit output location.

Required examples cover minimal compatibility, local override, modpack profile, declarative family provider, conflicting packs, target-specific behavior, and trusted adapters. Core built-in compatibility packs should eventually traverse the same canonical validation path, making MIR the reference consumer of MEP-1.

## SDK bundle

Each stable 3.3/2.6 release pair publishes a separate `mir-extension-sdk-1.x.zip` containing protocol schemas, portable registration helpers, templates, validators, packagers, migration tooling, offline builder, passing and failing examples, target examples, canonicalization and conflict vectors, quickstarts, protocol reference, cookbook, and forking guide.

The SDK must work without cloning the MIR repository.

## Protocol stability

All MIR 3.3.x and 2.6.x releases support MEP-1.x. A breaking protocol change creates MEP-2 rather than hiding the break in a MIR patch release.

When MEP-2 appears, MIR continues accepting MEP-1 for at least one complete modern/Factorio-2.0 release pair, publishes a migration tool for canonical manifests where possible, emits replacement diagnostics, and requires tombstones or explicit incompatibility for removed fields.

Unknown input policy is:

```text
unknown optional metadata       preserve or ignore safely
unknown optional fragment       quarantine the fragment and retain legal siblings
unknown required capability     reject the extension
unknown safety-critical action  reject the extension
```

Extensions depend primarily on named capabilities and versioned fragment/operator contracts, not exact MIR release numbers.

## Project continuity contract

MEP-1 is host-neutral and locally discoverable. A compatible fork advertises protocol name, version, capabilities, and target; it does not need the official repository, maintainer, package name, or online registry.

Factorio gives each mod its own persisted `storage` instance. Therefore a fork with a different internal mod name can preserve data-stage extension compatibility but does not automatically inherit the original mod's runtime storage. Runtime continuity requires the same internal name or an explicit migration bridge. This limitation must be documented and tested.

Official Factorio API reference: [Storage](https://lua-api.factorio.com/latest/auxiliary/storage.html).

Every stable release archives a continuity bundle containing source snapshot, Git bundle, toolchain lock, package generator, protocol schemas, SDK, reference extensions, vectors, target profiles, migration corpus, release runbook, evidence-root manifest, and public archive identities.

Planned governance surfaces are `GOVERNANCE.md`, `CONTRIBUTING.md`, `FORKING.md`, `PROJECT-CONTINUITY.md`, `MAINTAINER-HANDOFF.md`, `RELEASE-RUNBOOK.md`, `SECURITY.md`, and `EXTENSION-PROTOCOL.md`. They must explain stable IDs, release reconstruction, host capabilities, runtime-state migration, pack adoption, successor publication, and conformance testing.

Protocol schemas, helpers, examples, and conformance vectors require clear licensing that permits independent compatible implementations.

An optional community index may improve discovery, but no local extension load depends on it.

## Trust and claim maturity

Keep source authority, evidence maturity, behavior, and scope independent:

```text
source:    local | community | reviewed-community | core-reviewed | trusted-code
maturity:  unverified | observed | loads | fixture-qualified | exact-environment-qualified | release-qualified | stale | regressed | retired
behavior:  diagnostic | coexistence | attach | adopt | create | replace | repair
scope:     recipe | feature | family | subsystem | profile | pack
```

A local unverified attachment may work safely without becoming an official public support claim.

## Test and assurance matrix

Contract tests cover unique and duplicate IDs, identical and conflicting duplicate transports, unsupported majors, compatible minors, unknown fields, missing capabilities, applicability, dependency cycles, conflicts, selector and output budgets, safety-bypass attempts, local restrictions, and registration-order independence.

Transport tests cover multiple 2.1 `mod-data` declarations, the legacy singleton, mixed transports, host absence, alternate host, deduplication, the 2.0 stage bus, host wrapper, declaration timing, and registry freeze.

Target tests prove one semantic source produces explicit 2.1 and 2.0 packages with declared differences. Conflict tests cover same owner, different owners, local resolution, safety denial, authority limits, and exact reviewed version envelopes.

A synthetic alternate host named `mir-reference-fork` uses a different package name, implements MEP-1, discovers the same host-neutral test packs, produces equivalent normalized dispositions, and demonstrates the runtime-storage limitation.

Transition tests cover extension install, removal, version change, target-mod addition/removal, profile change, save/reload, and configuration change.

Every extension-aware proof binds extension ID and semantic digest, source mod version and release archive digest, protocol ABI, resolved capabilities, target, exact environment, and effective profile. A fragment change reruns only the proof closure that reads that fragment when semantic impact is proven sound.

## Integration with current MIR modules

`compatibility/packs/registry.lua` becomes a legacy singleton adapter plus unique `mod-data`, stage-bus, and host-module collectors feeding canonical fragments. `compatibility/packs/schema.lua` separates the extension envelope, compatibility fragment, evidence reference, and claim metadata.

`compatibility/policy_authority.lua` remains the sole planning facade and consumes core overlays, core packs, validated external fragments, profiles, claims, and resolved capabilities without learning transport details.

`providers/registry.lua` evolves into validated core providers, validated declarative providers, and separately registered trusted adapters.

`CompilerContext` owns one frozen immutable `extension_registry` artifact and derived accepted, quarantined, policy-fragment, and provider-fragment views.

`emit/mod_data.lua` continues target-aware publication of MIR compiler artifacts and adds the host capability inventory, accepted extension inventory, and compatibility report where the target supports that transport.

Target profiles declare supported extension transports, fragment types, runtime descriptors, operator versions, and omissions.

Control Plane v5 eventually adds explicit extension semantic domains and atomic tasks only when E0 introduces the schemas. The verification context binds accepted/quarantined inventories, dependency graph, capability resolution, semantic roots, and target dispositions; the release seal binds protocol ABI and the extension compatibility report.

## Delivery roadmap

### E0: characterize and specify

Freeze current pack behavior; capture built-in overlays, packs, claims, and providers; define MEP-1 schemas, namespaces, lifecycle, transports, safety, conflicts, budgets, ADRs, and golden vectors. No behavior change.

### E1: canonical extension registry

Add the envelope, unique `mod-data` collector, stage bus, legacy adapter, normalization, semantic deduplication, freeze, inventory, and shadow parity with current packs.

### E2: compatibility and profile API

Support compatibility and profile fragments, templates, scaffold/validate/test/package commands, minimal examples, and the same canonical validation path for built-ins.

### E3: offline builder

Import support bundles, provide Basic/Advanced/Expert modes, preview offline, generate standalone ZIPs, explain safety/conflicts, and ship extension doctor.

### E4: declarative family providers

Split the oversized provider contract, publish a bounded operator catalog, compose declarative providers, prove algebra and complexity, and keep new creation review-gated.

### E5: conflict and policy composition

Introduce field-specific merge laws, source authority classes, local resolution packs, complete traces, and the sealed safety boundary.

### E6: proof and community qualification

Add proof fragments, exact environments, claim expiry, community CI templates, optional index tooling, and snapshot replay.

### E7: advanced adapters

Introduce experimental `TrustedAdapterV1` with immutable inputs, data-only output, exact locks, declared reads, no mutation authority, and strict work budgets.

### E8: continuity fixed point

Publish the conformance suite separately, add the synthetic fork, run host disappearance/replacement drills, complete succession and release runbooks, and archive SDK/source bundles.

### E9: MIR 2.6 projection

Implement and qualify the Factorio 2.0 transport, project identical semantic fragments where capabilities permit, record target omissions, reconstruct deterministically, and independently seal 2.6.

## Definition of done

MEP-1 is complete when ordinary compatibility needs no MIR source edit; a player can generate a local pack without Lua; a mod author can embed data-only support; standalone packs are discovered automatically; independent packs combine deterministically; conflicts are actionable; local safe resolution works; hard safety remains sealed; hosts and packs require no central service; host-absent packs are inert; a differently named fork passes conformance; runtime migration limits are explicit; one manifest targets 3.3/2.1 and 2.6/2.0; protocol compatibility and migration are tested; impact is fragment-precise; the SDK is standalone; and archived local materials are sufficient to rebuild, test, extend, and release the ecosystem.

## Non-goals

Do not keep the singleton `mod-data` prototype as the permanent API, hard-depend every pack on official MIR, expose raw `CompilerContext` or mutation executors, let extensions write `data.raw` through MIR, accept arbitrary callbacks in stable declarative surfaces, let community metadata confer official support, resolve every field with numeric priority, use registration order as policy, generate startup settings from final prototypes, promise impossible finalizer ordering, require an online catalog, create a bridge for every minor rule, expose the full provider contract as the beginner API, couple protocol compatibility to MIR release numbers, ignore required unknown fields, allow unbounded input/output, or assume a differently named fork inherits runtime storage.

Related decisions and sequencing:

- [ADR 0030: Host-neutral MIR Extension Protocol v1](../adr/0030-host-neutral-extension-protocol.md)
- [MIR 3.3 and 2.6 convergence platform roadmap](3.3-2.6-convergence-platform-roadmap.md)
- [MIR 3.2.5 to 2.6 convergence programme](../releases/3.2.5-to-2.6-convergence-programme.md)
