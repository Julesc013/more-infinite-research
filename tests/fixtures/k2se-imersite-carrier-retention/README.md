---
title: K2SE Imersite hidden-carrier retention fixture
---

This fixture prepares an exact published 4.7.21003 K2SE (Krastorio2 2.1.4 plus Space Exploration 0.7.63, without Krastorio2 Spaced Out) F210 source save and passes its immutable ZIP to frozen b251ae7a54104ace87cb0da4cf531cf53f03c93d/player79b73a6a8e68987737e69bf2d95ec6555b49f901 MIR5 F210 input E3A65C08AC7798A66FB1BE30D24307B17C8B366DD901953BDE2A09BD6939C8CE (679250 bytes). It seeds `mir-k2-imersite-staged-state-1` and `mir-k2-imersite-continuation-state-4` as native saved state after source initialization, then proves their configured identity, effects, current/queued investment, detached saved progress, and an independently disabled foreign-force state before any successor fixture write.

The source seeds are not laboratory-earned historical evidence. No K2SO runtime bridge, public Imersite handoff, or laboratory completion is invoked or claimed; K2SO is deliberately absent. Both arms save once and the generic native runner performs its normal two cold reloads, while `on_load` only changes local callback flags.

The published source archive is B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852. The current target archive is E3A65C08AC7798A66FB1BE30D24307B17C8B366DD901953BDE2A09BD6939C8CE (679250 bytes). The profiles retain q013's upstream K2SE archive closure and its A15 observer archive. A15 and canonical 2E1 have the same tracked observer members but distinct archive containers; generic `Invoke-NativeFixture.ps1` binds the archive actually selected by the profile and does not treat them as interchangeable. Replaying a separate A15-prepared runtime container remains owner-side preparation, not a fixture exception.

The current carrier presentation has an icon-only correction relative to the historical published icon. This fixture intentionally checks runtime identity/effects and does not turn that presentation correction into a source-state mutation or a cross-version image equality claim. Native execution remains required.
