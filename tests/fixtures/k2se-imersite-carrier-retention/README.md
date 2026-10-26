---
title: K2SE Imersite hidden-carrier retention fixture
---

This fixture prepares an exact published 4.7.21003 K2SE (Krastorio2 2.1.4 plus Space Exploration 0.7.63, without Krastorio2 Spaced Out) F210 source save and passes its immutable ZIP to frozen MIR5 F210 input C563CB5B96C9E64CB3373BDB60CF5C8B7D3C97E93EADB8F924443C703CDC024D. It seeds `mir-k2-imersite-staged-state-1` and `mir-k2-imersite-continuation-state-4` as native saved state after source initialization, then proves their configured identity, effects, current/queued investment, detached saved progress, and an independently disabled foreign-force state before any successor fixture write.

The source seeds are not laboratory-earned historical evidence. No K2SO runtime bridge, public Imersite handoff, or laboratory completion is invoked or claimed; K2SO is deliberately absent. Both arms save once and the generic native runner performs its normal two cold reloads, while `on_load` only changes local callback flags.

The published source archive is B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852. The current target archive is C563CB5B96C9E64CB3373BDB60CF5C8B7D3C97E93EADB8F924443C703CDC024D (568598 bytes). The profiles retain q013's upstream K2SE archive closure and its A15 observer archive. A15 and canonical 2E1 have the same tracked observer members but distinct archive containers; generic `Invoke-NativeFixture.ps1` binds the archive actually selected by the profile and does not treat them as interchangeable. Replaying a separate A15-prepared runtime container remains owner-side preparation, not a fixture exception.

The current carrier presentation has an icon-only correction relative to the historical published icon. This fixture intentionally checks runtime identity/effects and does not turn that presentation correction into a source-state mutation or a cross-version image equality claim. Native execution remains required.
