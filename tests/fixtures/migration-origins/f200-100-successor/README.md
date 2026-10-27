---
title: MIR 1.0.0 F200 migration-origin successors
---

This fixture is a private successor observer for the protected MIR 1.0.0 F200 source save. It deliberately retains the source fixture mod identity and storage key so that configuration change loads the exact original state rather than manufacturing a replacement baseline.

The F200 wrapper is version `0.2.0` and admits only Base 2.0.77 with MIR `5.0.20000`. The F210 wrapper is version `0.3.0` and admits only Base 2.1.23 with MIR `5.0.21000`; it consumes the separately protected completed F200 successor save. Both wrappers are staged as `info.json` from the target-specific metadata file and have no alternate runtime members.

Before any candidate work, the control reads all retained source rows, state fields, recipe bonuses, effect signatures, foreign queue, detached work, manual-mining offset, and the effective false breeding setting. It does not seed, normalize, compensate, or silently skip a source row. Source science and cost remain historical facts; the candidate gear lab uses the candidate's actual runtime science list after the observer data stage has reduced only that lab's count and time.

One real candidate gear completion is required for each successor. It is recorded separately from the one historical source lab, then the completed save must survive two read-only cold reloads. This fixture makes no physical-factory, performance, or release claim.
