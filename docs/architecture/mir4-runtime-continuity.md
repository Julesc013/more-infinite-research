---
title: "MIR 4 Runtime, State, Migration, and Continuity"
status: current
applies_to: "4.0.0 M4C02-09-24H"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
---
# MIR 4 runtime, state, migration, and continuity

W04 formalizes the existing player runtime without rewriting it. `control.lua`, the stage control entrypoint, `prototypes/mir/runtime/**`, the Factorio runtime-state adapter, and `migrations/**` remain the only player-authoritative runtime and migration implementation. The W04 programme is package-excluded and may verify, hash, simulate laws, and project contracts; it cannot register handlers, mutate a save, execute a migration, alter prototypes, or claim public continuity.

`RuntimeFeatureSpecV1` gives each current feature a stable identity, source hash, target requirements, handler symbols, event and complexity budgets, state references, migration references, and removal behavior. Symbols are references to the current Lua handlers, not callbacks. The registration plan preserves the current subscriber order as explicit ordinals and proves one registration per event/filter group, filtering before dispatch, duplicate rejection, no persistent `on_load` mutation, no idle `on_tick`, namespace isolation, and bounded diagnostics.

`StateSpecV1` classifies fields rather than whole buckets. Spoilage baseline and last-applied ownership values, plus maximum-level enable and visibility restoration values, are authoritative state. Agricultural multipliers and adoption metadata are reconstructible. Maximum-level observations and the dispatcher allocation bucket are disposable caches. Namespaces are derived from the target profile: `storage.mir.*` for f210/f200 and `global.mir.*` for legacy profiles. A compiled-out target receives no fabricated active runtime.

The migration graph covers same-target upgrades, skipped patches, cross-target transitions, extension install/remove, ownership transfer, profile/schema transition, repair, and explicit downgrade disposition. Existing migration JSON and runtime repairs are evidence rows, not proof that every transition is qualified. f210/f200 remain runtime-proof-required; f110/f100 and explicit historical profiles compile scripted runtime out; terminal-derived f014/f013 remain opaque; museum targets remain blocked with evidence.

The private continuity bundle binds target contracts, providers, profiles, predecessor research identities, runtime schemas, module closure, extension-closure status, aliases/tombstones, migration watermark, package roots, proof roots, and a redaction manifest. W05 owns external extension closure and W06 owns ProcessIR semantics. The bundle is not public release proof.

Rollback removes only W04 authorities, schemas, generated projections, and build records, then restores the W03 subscription and migration laws to deferred. It never deletes or rewrites player state or existing migrations.
