---
title: MIR 1.0.0 F200 migration-origin successors
---

This fixture is a private successor observer for the protected MIR 1.0.0 F200 source save. It deliberately retains the source fixture mod identity and storage key so that configuration change loads the exact original state rather than manufacturing a replacement baseline.

The F200 wrapper is version `0.2.0` and admits only Base 2.0.77 with MIR `5.0.20000`. The F210 wrapper is version `0.3.0` and admits only Base 2.1.23 with MIR `5.0.21000`. Both begin directly from the same immutable MIR1 source save; no intervening MIR5 installation is part of either origin claim. Both wrappers are staged as `info.json` from the target-specific metadata file and have no alternate runtime members.

Before any candidate work, the control reads all retained source rows, state fields, recipe bonuses, effect signatures, foreign queue, detached work, manual-mining offset, and the effective false breeding setting. It does not seed, normalize, compensate, or silently skip a source row. The wrapper supplies the source's observed false breeding startup input for this bounded successor load; it does not claim that the historical fixture default was a user-authored override that persists through a later default change. Source science and cost remain historical facts; the candidate gear lab uses the candidate's actual runtime science list after the observer data stage has reduced only that lab's count and time.

The source fixture itself seeded and snapshotted the player, foreign, and detached manual-mining offsets. Current-engine configuration has been observed to reset that fixture-owned sentinel before callbacks, so configuration re-applies exactly those three saved values before the strict retained-state check and logs the pre-reapply values. It does not restore arbitrary script or console modifiers, and cold reloads never write the sentinel.

One real candidate gear completion is required for each successor. It is recorded separately from the one historical source lab, then the completed save must survive two read-only cold reloads. This fixture makes no physical-factory, performance, or release claim.
