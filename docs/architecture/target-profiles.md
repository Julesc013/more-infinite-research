---
title: "Target Capability Profiles"
status: current
applies_to: "3.0.5+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Target Capability Profiles

`.mir/targets.json` is the canonical target-line capability manifest. JSON is used deliberately: PowerShell can consume it without an external YAML module, and a deterministic build step can generate Lua compatible with old Factorio targets that do not expose a common JSON helper during prototype loading.

The checked-in Lua view is `prototypes/mir/platform/factorio/target_profiles.lua`. Generate it with:

```powershell
.\scripts\Sync-MIRTargetProfiles.ps1
```

Static and architecture validation run the same command with `-Check` and fail when the generated view differs from `.mir/targets.json` or the active `info.json` target. PowerShell validation reads the canonical JSON directly through `scripts/validation/TargetProfiles.ps1`; it does not maintain a second hand-written target classification.

Every profile is now a `TargetProfileV2` record and declares:

- support class and validation status;
- `storage` or `global` runtime state backend;
- science-family identity;
- modern, reduced, and Factorio 2.0 validation classifications;
- Space Age capability;
- weapon-overlap default;
- technology overlay policy;
- feature switches;
- positive recipe, science-pack, probability, formula, quality, and surface-condition shapes;
- available emitter families, asset policy, and expected stream count;
- positive supported mod namespaces and technology effect types on every declared line;
- required validation groups.

`target_line.lua` converts the selected profile into the stable adapter API used by settings, planning, emission, stage orchestration, and runtime state. Target profiles classify capabilities; they do not create or mutate prototypes.

For every target, stream descriptors declare required features, mods, prototypes, technologies, and effect types. The selected profile must positively admit every required feature, mod namespace, and effect type. No profile may carry the older `unsupported_streams`, `unsupported_required_mods`, `unsupported_effect_types`, or `omitted_global_settings` denylists. Reduced profiles use empty positive allowlists and disabled features to fail closed; this is a contract shape, not a binary support claim.

The same positive declaration rule applies to generated settings, pipeline commands, runtime event handlers, and governed fixtures. An empty `requires_features` array is an explicit portable declaration, not missing metadata. Architecture lint fails when a handler or fixture omits its declaration. Cross-target fixtures obtain science-pack prototype kind and stream-count expectations from TargetProfileV2 rather than branching on Factorio version or hard-coding modern values.

Profiles for released lines record validated historical behavior. Profiles for Factorio 0.16 and 0.15 are explicitly marked as planned and do not constitute binary support claims. Their science and effect surfaces still require matching target-binary proof.

## Runtime State

`prototypes/mir/platform/factorio/runtime_state.lua` is the only production Lua module that accesses Factorio's persisted runtime root directly. Factorio 2.x profiles select `storage`; Factorio 1.1 and older profiles select `global`. Runtime feature modules consume `prototypes/mir/runtime/state.lua` and cannot probe both names or silently choose a fallback.

## Backport Rule

When a target branch changes `info.json`, regenerate the Lua profile view and run architecture validation. Target-local capability changes must first update the canonical manifest and must not weaken the Factorio 2.1 profile. The unrestricted module-permission pass has its own `module_permissions` feature flag. Its setting registration, target capability, and executable pass must agree; it does not inherit support from `prototype_limits`.
