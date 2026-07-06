---
title: "MIR 3.0.0 Compatibility Compiler Charter"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# MIR 3.0.0 Compatibility Compiler Charter

Updated: 2026-07-07

This note records the intended shape of `3.0.0` after the `2.2.0` current-line
release and the `1.9.2` Factorio `2.0` transition backport. It is an
architecture charter, not a promise to add every requested productivity idea in
one release.

The short version:

```text
MIR 3.0.0 = the compatibility compiler release.
```

It should not be framed as:

```text
MIR 3.0.0 = productivity for everything.
```

## Current Position

`2.2.0` already starts the bounded procedural direction:

```text
discover prototypes
normalize facts
resolve capabilities
classify families and risks
propose ownership
validate gates
emit approved streams
observe unknowns
fixture-test decisions
```

The `2.2.0` kernel proves this with typed facts, capability diagnostics,
DecisionRecord-style rows, stream manifest linting, compatibility claims,
negative fixtures, and report drift tooling.

`3.0.0` should turn that proven kernel into the public architecture contract.
That means stable module boundaries, schema-versioned intermediate records,
policy overlays, generated-ID migration rules, fixture-backed claims, and
maintainer workflows that can scale to K2, Bob's, Angel's, Space Exploration,
Pyanodons, AAI, and other large mod sets without becoming a pile of
mod-specific generation scripts.

## Release Charter

`3.0.0` converts More Infinite Research into a modular compatibility compiler.

It separates:

- prototype discovery;
- fact normalization;
- classification;
- capability resolution;
- policy decisions;
- technology emission;
- reporting;
- fixtures;
- migrations.

It preserves conservative behavior. MIR auto-emits only high-confidence,
policy-approved, lab-compatible, ownership-safe, loop-safe technologies.
Everything else becomes diagnostics, policy stubs, fixture work, or explicit
future scope.

The key rule:

```text
3.0.0 is not "productivity for everything."
3.0.0 is "a framework that can safely decide what productivity support means."
```

## Core Pipeline

The 3.0 compiler pipeline should be:

```text
FactRegistry
-> CapabilityCandidate[]
-> ClassificationRecord[]
-> StreamProposal[]
-> DecisionRecord[]
-> StreamSpec[]
-> EmittedPrototype[]
-> ReportArtifact[]
```

Each stage has a single job:

| Stage | Responsibility |
| --- | --- |
| Facts | Snapshot what exists in final prototype state. |
| Capabilities | Decide what MIR knows how to reason about. |
| Candidates | Represent possible targets before policy. |
| Classification | Assign family, subfamily, confidence, evidence, and risks. |
| Policy | Decide whether MIR may emit, observe, reject, or defer. |
| Decision records | Explain every generated and non-generated outcome. |
| Stream specs | Carry validated prototype-emission intent. |
| Emitters | Mutate `data.raw` only after validation. |
| Reports | Persist stable evidence for users, fixtures, and audits. |
| Migrations | Preserve released generated technology identities. |

## Required Layer Boundaries

The 3.0 codebase should enforce one-way boundaries:

```text
facts/ may read data.raw, but may not emit prototypes.
classify/ may read facts, but may not read data.raw directly.
graph/ may read facts and classifications, but may not emit prototypes.
policy/ may read facts, classifications, graphs, and settings, but may not emit prototypes.
planner/ may create DecisionRecords and StreamSpecs, but may not mutate data.raw.
emit/ is the only layer allowed to create or mutate technology prototypes.
report/ may serialize decisions, but may not alter prototypes.
compat/ may register policies, but may not build technologies directly.
fixtures/ may assert outputs, but may not define runtime behavior.
```

This boundary is the difference between a maintainable compiler and a growing
set of special-case compatibility files.

## Proposed Module Layout

The concrete repository-structure target is
`docs/architecture/module-boundaries.md`. That note is the active source for
the Factorio shell, `prototypes/mir/` compiler namespace, platform adapter,
development workspace, legacy shims, and architecture lint rules. The summary
below is the older high-level shape and should be read as conceptual, not as the
complete migration checklist.

The long-term layout should move toward:

```text
prototypes/
  data-final-fixes.lua
  mir/
    core/
      schema.lua
      ids.lua
      stable-sort.lua
      errors.lua
      diagnostics.lua

    facts/
      registry.lua
      recipes.lua
      items.lua
      fluids.lua
      entities.lua
      technologies.lua
      labs.lua
      machines.lua
      resources.lua
      modules.lua
      owners.lua
      rule-surfaces.lua

    graph/
      recipe-graph.lua
      technology-graph.lua
      science-graph.lua
      resource-chain-graph.lua
      loop-risk.lua

    classify/
      recipe-family.lua
      item-family.lua
      entity-family.lua
      machine-family.lua
      science-family.lua
      risk-flags.lua

    capabilities/
      registry.lua
      contract.lua
      recipe-productivity.lua
      machine-manufacturing.lua
      logistics-manufacturing.lua
      loader-manufacturing.lua
      mining-drill-manufacturing.lua
      native-modifiers.lua
      mining-yield.lua
      belt-stack.lua
      lab-productivity.lua
      ore-processing.lua
      tile-surface.lua
      science-integration.lua
      rule-surface-observer.lua

    policy/
      defaults.lua
      settings.lua
      capability-policy.lua
      family-policy.lua
      modpack-policy.lua
      owner-policy.lua
      cap-policy.lua
      science-policy.lua
      denylist.lua

    planner/
      candidate.lua
      classifier.lua
      scorer.lua
      validator.lua
      decision-record.lua
      plan.lua

    emit/
      stream-spec.lua
      technology-builder.lua
      locale-builder.lua
      icon-builder.lua
      manifest.lua
      migration.lua

    report/
      observations.lua
      planner-report.lua
      fixture-export.lua
      claim-export.lua
```

Named compatibility files should become declarative overlays:

```text
compat/
  base.lua
  space-age.lua
  air-scrubbing.lua
  atan-ash.lua
  atan-nuclear-science.lua
  aai-industry.lua
  aai-loaders.lua
  bob-materials.lua
  krastorio2.lua
  krastorio2-spaced-out.lua
  angels.lua
  space-exploration.lua
  pyanodons.lua
```

These overlays register selectors, exact IDs, denylists, policy overrides,
claim text, and fixture expectations. They should not build technologies
directly.

## 3.0 Invariants

These are hard architecture rules:

1. Only emit from validated `StreamSpec` records.
2. Every generated technology has a manifest entry.
3. Every planner decision has a `DecisionRecord`.
4. Every auto-emitted candidate has evidence, confidence, and policy provenance.
5. Unknown candidates are reported, not ignored.
6. Loop-risk candidates are diagnostic-only unless explicitly overridden.
7. External owners are preserved unless exact cleanup or adoption policy passes.
8. Added science packs are included only when science and lab validation passes.
9. Generated technology IDs are stable after release.
10. Released generated streams are never silently renamed or removed.
11. Startup settings control prototype mutation.
12. Runtime code is not required for normal static productivity streams.
13. Compatibility claims are backed by fixtures.
14. Package contents stay clean and exclude developer-only artifacts.

## Capability Split

The architecture must keep distinct mechanisms separate:

| User-facing idea | MIR lane | Factorio mechanism |
| --- | --- | --- |
| More output when crafting filters, loaders, drills, or machines | Recipe productivity | `change-recipe-productivity` |
| Mining drills produce more ore | Native mining yield | `mining-drill-productivity-bonus` |
| Belts/loaders carry stacked items | Native logistics | `belt-stack-size-bonus` |
| Labs produce more research | Native lab productivity | `laboratory-productivity` |
| Labs research faster | Native lab speed | `laboratory-speed` |
| Added science packs work correctly | Science/lab integration | technology unit ingredients, prerequisites, lab inputs |
| A mod mutates modules, beacons, caps, or productivity rules | Rule-surface diagnostics | observation/policy, not blind mutation |

Do not collapse these into one vague "productivity" bucket.

## What 3.0 Should Fix

3.0 should finish the architecture started in 2.2:

- replace feature-specific generation paths with capability resolvers;
- make schemas first-class;
- move compatibility files toward policy overlays;
- enforce layer boundaries;
- make generated stream manifests part of save compatibility;
- add compatibility claim manifests and claim linting;
- expand negative fixtures;
- make report diffing part of normal compatibility review;
- lint policy overlays;
- make ordering deterministic;
- add performance budgets for large compatibility targets;
- create public ADRs for decisions we should not rediscover.

## What 3.0 Should Not Do Automatically

Do not ship these as automatic 3.0 behavior:

- productivity everywhere;
- productivity cap mutation;
- beacon productivity;
- quality in beacons;
- recycler productivity;
- broad research-cost mutation;
- runtime production-stat productivity;
- global throughput rewrites;
- full Space Exploration generation;
- full Pyanodon generation;
- automatic matter/transmutation productivity;
- automatic core-fragment productivity;
- automatic tile/foundation high-value productivity;
- external owner replacement without exact proof.

3.0 may observe these surfaces, report them, fixture-test them, and create
policy stubs for future review. That is not the same as emitting gameplay
changes.

## Content Boundary

3.0 should include only enough behavior to prove the architecture:

- existing explicit MIR streams migrated behind `StreamSpec`;
- existing Air Scrubbing clean-filter support migrated through the capability
  and policy path;
- loader manufacturing as report-first structural candidates;
- mining-drill manufacturing as report-first structural candidates;
- native modifier owner observations;
- ATAN Nuclear Science as a science/lab fixture;
- one ore-crushing stream only if the full safety stack passes.

It should not be the release for broad K2, Bob's, Angel's, Space Exploration,
Pyanodons, native mining-yield emission, tile/foundation productivity, beacon
changes, module-rule changes, or runtime productivity systems.

## Suggested Release Ladder

### `3.0.0-alpha.1`: Skeleton And Contracts

- Create the `mir/` module tree.
- Add schema validators.
- Add the capability resolver contract.
- Add `DecisionRecord` v1.
- Add `StreamSpec` v1.
- Add `StreamManifest` v1.
- Add policy overlay schema and linter.
- Add stable ID helpers.
- Add no new gameplay behavior.

### `3.0.0-alpha.2`: Current Behavior Through Phases

- Move current explicit stream generation behind `StreamSpec`.
- Move Air Scrubbing through capability and policy.
- Move owner, cap, lab, and loop diagnostics into report modules.
- Make `emit/` the only layer that mutates technologies.
- Preserve existing generated technology IDs.

### `3.0.0-alpha.3`: Fact Registry V2

- Expand facts for items, entities, resources, modules, labs, machines, owners,
  and rule surfaces.
- Add entity-backed item and recipe links.
- Add loader and mining-drill facts.
- Add machine base productivity facts.
- Add rule-surface facts for caps, modules, beacons, recyclers, and labs.

### `3.0.0-alpha.4`: Capability Registry

- Recipe productivity capability.
- Machine manufacturing capability.
- Loader manufacturing capability, report-only unless an existing stream owns it.
- Mining-drill manufacturing capability, report-only unless an existing stream
  owns it.
- Native modifier capability, observe-only.
- Science/lab integration capability.

### `3.0.0-beta.1`: Graph And Safety

- Recipe graph.
- Technology graph.
- Science graph.
- Resource-chain graph.
- Loop-risk scanner.
- Negative fixtures.
- Report diff tool.

### `3.0.0-beta.2`: Real Compatibility Proof

- Revalidate Air Scrubbing through the new architecture.
- Add ATAN Nuclear Science science/lab fixture.
- Add AAI Loaders report-only fixture.
- Add generic mining-drill report-only fixture.
- Add Crushing Industry or ore-crushing only if all gates pass.

### `3.0.0-beta.3`: Docs And Claims

- Public compatibility claim manifest.
- Compatibility matrix generated or checked from claims.
- README updated for the 3.0 model.
- Migration guide.
- Maintainer guide.
- ADRs.

### `3.0.0-rc.1`: Release Gate

- Full static validation.
- Factorio-backed runtime validation.
- Package hygiene validation.
- Fixture lockfiles.
- Clean report diffs.
- Stable generated manifest.
- No unexpected technology ID changes.

## Acceptance Gates

Before `3.0.0` can release:

- `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly` passes.
- Factorio `2.1` runtime validation passes.
- `.\scripts\mir.ps1 release gate --profile release-targeted-2.1 --no-git-pull`
  passes.
- Policy lints pass.
- Manifest lints pass.
- Claim lints pass.
- Negative fixtures pass.
- Report diff for the final candidate is reviewed.
- Public docs make no unbacked "full support" claims.
- The release archive excludes docs, fixtures, scripts, task ledgers, and
  other developer-only payloads.

## Backport Boundary

Backport 3.0 only after the Factorio `2.1` line is stable:

1. Tag or record the tested 3.0 source commit.
2. Create target-line `tmp/*` worktrees.
3. Apply target-line metadata and API guards.
4. Validate with matching Factorio binaries and mod libraries.
5. Bring portable fixes back to `dev`.
6. Publish only target lines that pass their own gates.

If an older Factorio line cannot support a surface, disable or remove that
surface and document the exclusion. Do not simulate feature parity.

## Reference API Surfaces

The compiler design depends on these Factorio prototype concepts:

- technology effects are `Modifier` records;
- technologies support `effects`, `unit`, prerequisites, hidden state, and
  `max_level = "infinite"`;
- recipes expose productivity-related fields such as `allow_productivity` and
  `maximum_productivity`;
- labs declare accepted science pack inputs;
- loader and mining-drill prototypes give structural entity facts;
- mod loading separates data-stage prototype construction, control-stage
  runtime scripting, and migrations.

Keep `docs/reference/factorio-api-proof-points.md` current when any of these assumptions changes.
