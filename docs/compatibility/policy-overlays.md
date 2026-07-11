---
title: "Policy Overlays"
status: current
applies_to: "3.0.0+"
audience: modpack-author
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# Policy Overlays

Updated: 2026-07-07

Policy overlays are declarative compatibility rules. They say what MIR is allowed to do when a prototype set or known mod is present. They should not build technologies directly.

## Boundary

Bad:

```lua
if mods["bobplates"] then
  add_tech("bob-brass")
  add_tech("bob-bronze")
end
```

Good:

```lua
register_policy_overlay({
  id = "bobplates.alloy",
  schema_version = 1,
  applies_when = { mod = "bobplates" },

  capabilities = {
    ["recipe-productivity.material-family"] = {
      mode = "safe",
      family = "alloy",
      selectors = {
        subgroup_contains = { "alloy" },
        result_name_contains = {
          "brass",
          "bronze",
          "invar",
          "nitinol",
        },
      },
      deny_risk_flags = {
        "recycling_loop",
        "catalyst_loop",
        "recovery_loop",
        "voiding",
      },
      science = {
        mode = "derive_from_unlocks",
        require_lab_compatible = true,
      },
    },
  },

  claim = {
    level = "planned_family_support",
    text = "Bob's alloy productivity is planned as a family-scoped policy.",
  },
})
```

The overlay describes selectors, policy, risks, science, and claim intent. The compiler still discovers facts, classifies candidates, validates the plan, and emits only through `StreamSpec`.

## Policy Modes

| Mode | Meaning |
| --- | --- |
| `off` | Do nothing and suppress proposals for this lane. |
| `observe` | Emit diagnostics only. |
| `propose` | Emit report stubs for maintainer review, but no prototypes. |
| `safe` | Auto-emit only when every gate passes. |
| `exact` | Auto-emit only for explicit recipe or effect IDs. |
| `diagnostic_only` | Always explain, never emit. |

## Required Fields

Every policy overlay should include:

- `schema_version`;
- stable `id`;
- `applies_when` selector;
- capability ID;
- mode;
- owner policy;
- science policy;
- deny-risk flags;
- minimum confidence when auto-emitting;
- claim text or explicit `claim = false`.

## Lint Rules

The policy linter should fail when:

- a policy lacks `schema_version`;
- a policy lacks a capability ID;
- `safe` or `exact` mode lacks minimum confidence;
- auto-emission lacks deny-risk flags;
- native modifier policy lacks owner policy;
- hidden recipes are targeted without an explicit reason;
- science fallback lacks a lab check;
- a policy mutates caps by default;
- a public claim lacks a fixture;
- a generated stream lacks a manifest row;
- an overlay directly mutates `data.raw`.

## Claim Discipline

Claim the behavior, not a brand label:

- "loader recipes are covered by belt productivity when visible";
- "mining-drill recipes are covered by mining drill productivity when visible";
- "science-pack recipes are covered when the pack is an active lab input";
- "Air Scrubbing clean-filter crafting only."

Avoid "full support" unless fixtures prove the full claim.
