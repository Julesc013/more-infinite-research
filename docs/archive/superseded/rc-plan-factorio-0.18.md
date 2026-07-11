---
title: "Factorio 0.18 Bridge Planning Report"
status: archived
applies_to: "0.18"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: ["../../maintainer/backporting.md"]
---
# Factorio 0.18 Bridge Planning Report

Updated: 2026-07-10 Branch: `port/1.1-to-0.18` Target Factorio line: `0.18.x` Planned MIR release slot: `1.8.0` Risk rating: High Change type in this commit: documentation and planning only; no code behavior changes.

`1.8.0` is a one-time bridge/archive package, not the maintained Factorio `1.0` support line. It should be seeded from the validated `1.9.3` Factorio `1.1` compatibility source point, retargeted to Factorio `0.18`, and validated as the exact same zip in both Factorio `0.18` and Factorio `1.0`.

## Release Identity

Metadata target:

```json
{
  "version": "1.8.0",
  "factorio_version": "0.18",
  "dependencies": [
    "base >= 0.18"
  ]
}
```

Release wording:

```text
MIR 1.8.0 is a Factorio 0.18 bridge/archive compatibility port derived from
the MIR 3 architecture and the Factorio 1.1 compatibility port.

It is provided for players on the final Factorio 0.18 experimental line and is
also used as the Factorio 1.0 bridge proof under Factorio's documented
0.18-to-1.0 compatibility exception.

This is not the maintained Factorio 1.0 line; MIR 1.8.1 and later are the
Factorio 1.0 support line.
```

## Required Cuts

- No recipe productivity unless the `0.18` binary proves the exact modifier.
- No Space Age, Quality, Recycler, Elevated Rails, cargo logistics, spoilage, agriculture, or Factorio `2.x` prototype repairs.
- No `storage`; use `global` or omit runtime state.
- No `2.x` dependency syntax.
- No newer graphics bundled from later Factorio versions.

## Candidate Surface

Keep only what the target binary accepts:

- `max_level = "infinite"` and `count_formula`;
- modern non-Space-Age science packs;
- target-proven direct-effect technology modifiers;
- base technology continuations;
- stock target-era icon sources and overlays;
- conservative startup settings for supported streams.

Probe in the `0.18` binary before release:

- lab productivity;
- worker robot battery;
- effect icon schema;
- technology icon schema;
- migration behavior;
- every generated direct effect.

## Validation Gates

- [ ] Create `port/1.1-to-0.18` from the validated `1.9.3` source point.
- [ ] Retarget `info.json` to `1.8.0`, Factorio `0.18`, and `base >= 0.18`.
- [ ] Remove or guard every target-rejected surface.
- [ ] Build `dist/more-infinite-research_1.8.0.zip`.
- [ ] Run static validation.
- [ ] Load the package in Factorio `0.18`.
- [ ] Load the exact same zip in Factorio `1.0`.
- [ ] Record SHA-256, size, entry count, forbidden-path count, source commit, binary versions, supported surface, and exclusions.
- [ ] Publish only after both binary loads pass.
- [ ] Freeze `1.8.0` after publication unless a severe package/load defect is found.
