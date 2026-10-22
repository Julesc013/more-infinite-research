---
title: "Support and upgrade boundaries"
status: draft
applies_to: "MIR replacement development"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-support-guide
---

# Support and upgrade boundaries

## Current scope versus intention

The replacement is under development. This documentation does not announce a released MIR 5 package, completed migration, universal mod support or measured speedup. Use the actual published release and its stated limitations until a qualified replacement is available.

Stable replacement scope must retain delivered applicable research, settings, effects, native continuations, prototype overrides, scripted features, the Library, bundled integrations and each supported engine edition's actual subset. New unimplemented ideas remain the original backlog; they are not silently marked complete.

An ecosystem name is not a test result. Support records should identify exact Factorio and upstream versions/settings, whether the technology is present, researchable, effective, physically productive, upgrade-safe, reload-safe, multiplayer-tested and performance-measured. Load-only evidence is labelled load-only.

## Safe diagnosis

Record Factorio/MIR version, exact archive identity where reissues existed, enabled mods/settings, the relevant log and a reproducible save when shareable. Preserve originals. Do not ask a player to repeatedly risk their only save, downgrade a resaved factory or disable a required mod as an assumed recovery.

For a new optional unsupported addition, MIR can omit that addition with a useful reason. Existing earned research requires a preservation/migration decision. A crash suppressed by deleting the technology is not a fix.

## Relevant retained incident subjects

Science trigger/output chains and independently available alternatives; specialist/resource science and labs; native-owner collisions; staged material/K2 progression; hidden credit carriers; caps and uncapping; foreign force offsets; manufacturing versus mining; settings imports and zero/inherit values; module/recycling safeguards; runtime registration; personal Library views and stale translations.

The original request/issue IDs and independent expected behavior must remain discoverable after source cleanup. Keep small current tests and pinned historical references, not old contradictory architecture documents in the active tree.

## Performance claims

Report whole-game startup separately from MIR-added startup. Headless creation/save, responsive menu, save load, first Library use and simulation are separate measurements. A one-technology demo or source-size reduction cannot establish the full replacement's performance. Missing data is inconclusive, not a proof of non-regression.
