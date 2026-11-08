---
title: "Named unknown-cost fallback fixture"
status: prepared
applies_to: "MIR unpublished 5.0.11 F210 qualification"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-09
supersedes: []
superseded_by: []
---

# Named unknown-cost fallback fixture

- Recover the existing eligible C503 r02 case: one unknown-polynomial foreign steel owner and one independently authored uncovered steel recipe. [The definition](definition.json) retains exact original paths, hashes, expectations and remaining admission checks; [the original review](../../../spec/evidence/candidate503-fallback-native-aero-review-r01.json) remains scoped to its actual old execution.
- Preserve all behavior. Only strict MIR and fixture version pins change to `5.0.21011` and `0.2.0`; the three helper Lua bodies are unchanged. The original invalid r01 producer and its failure remain historical evidence.
- Stage `control.lua` as the scenario actor. Package only the four files in `helper/` as `mir-fixture-native-owner-fallback`; that mod has no control stage. Do not package this parent directory or execute the actor twice.
- Expect configured cost `2/3/1.25`, one-second time and 17% reward; one actual lab completion grants only the named fixture recipe its 17%, consumes two of each four science packs, stops the lab, saves and survives two read-only cold loads. Native steel/casting/bullet rewards remain unearned and the foreign control remains unchanged.
- Read raw Git members from one exact committed revision before staging. Windows working-tree line endings are not interchangeable with those source hashes.
- The [profile](../../profiles/native-owner-fallback-current-f210-2123.json) declares seven mods but deliberately has no archive hashes. It is preparation only. Black Glass must bind the final reviewed player, fixture, engine/API/data and existing controller, complete guarded composition and obtain independent admission before running it. No native, physical-manufacturing, arbitrary-settings, client, performance or stable acceptance follows from these files.
