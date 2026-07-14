---
title: "Compatibility Claims"
status: current
applies_to: "3.0.0+"
audience: modpack-author
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# Compatibility Claims

Updated: 2026-07-07

Compatibility claims are machine-readable statements about what MIR has actually proved. They prevent public docs from saying "full support" when the evidence only proves load compatibility, diagnostic observation, or one narrow family.

## Claim Levels

| Level | Meaning |
| --- | --- |
| `loads` | MIR and the target mod load together. |
| `observed` | MIR reports facts/candidates but emits no behavior. |
| `cooperates` | MIR intentionally avoids conflicts with the target mod. |
| `diagnostic-only` | MIR recognizes a family and refuses to mutate it. |
| `partial-support` | Some fixture-backed behavior emits. |
| `full-family-support` | One named family is fully covered with positive and negative fixtures. |
| `full-pack-support` | The whole target mod or pack has a locked behavior matrix. Rare. |

## Claim Manifest Shape

```json
{
  "mod": "atan-air-scrubbing",
  "claim_level": "full-family-support",
  "factorio_lines": {
    "upstream_advertised": ["2.0"],
    "tested": ["2.1"]
  },
  "capabilities": {
    "recipe-productivity.clean-filter": "generated",
    "recipe-productivity.scrubbing-environmental": "diagnostic-only",
    "recipe-productivity.cleaning-recovery": "diagnostic-only"
  },
  "generated_streams": [
    "mir-prod-air-scrubbing-clean-filter"
  ],
  "fixtures": [
    "fixtures/air-scrubbing"
  ],
  "public_text": "Clean-filter crafting productivity only; scrubbing and cleaning recipes remain diagnostic-only."
}
```

## Repository And Lua Records

`.mir/compatibility.yml` is the repository-governance source for compatibility targets, docs, claim levels, fixture evidence, and public claim rules. `fixtures/compat-matrix/claims.json` is the fixture/audit claim record copied into scenario outputs.

`prototypes/mir/compatibility/claim_registry.lua` mirrors the small data-stage/report subset needed by MIR Lua. It is not a separate public claim authority; it must stay aligned with `.mir/compatibility.yml` and the fixture claim JSON.

## Lint Rules

The claim linter should fail when:

- docs say "full support" but the manifest is lower than `full-pack-support`;
- a compatibility matrix row has no claim manifest entry;
- a claim references a generated stream with no manifest row;
- a claim says `full-family-support` without positive and negative fixtures;
- a claim implies an upstream Factorio line that has not been tested;
- public text says MIR changes throughput, mining yield, caps, beacons, module rules, pollution removal, recovery loops, or external balance without an implemented policy and fixture.

## Public Wording

Use narrow wording:

```text
Added fixture-backed Air Scrubbing clean-filter productivity support for clean
filter crafting recipes only.

MIR intentionally does not add productivity to scrubbing, cleaning, recovery,
environmental-removal, or unknown related recipes. Those recipes are reported
through compiler diagnostics.
```

Avoid:

```text
Full Air Scrubbing support
Pollution productivity support
Automatic support for all Air Scrubbing recipes
```
