---
title: MIR 1.1.0 F200 migration-origin source fixture
---

This disposable source-only fixture prepares one Factorio 2.0.77 save from the exact public `more-infinite-research` 1.1.0 archive. It is a direct-F200 origin input for separately pinned same-engine and F210 successors. It is not a migration pass, current-package result, performance result, or release qualification.

The source package is the official GitHub `1.1.0` release asset `more-infinite-research_1.1.0.zip`, SHA-256 `6395C4A5A0F74C67729746D0FBF6162329978B47C5C29D54CC0045F2977C7E44`, 60,927 bytes. Its tag source is `2fb64822b82569e3b50f0653e361fb7148f18b63`; the archive is not reconstructed from that source tree.

The fixture pins all 42 published startup defaults in its finite `settings-final-fixes` stage: the space gate and every stream are enabled except the disabled inventory stream. Its `data-final-fixes` stage reads only effective startup settings and checks the 31 F200-emitted source rows against literal 1.1.0 config and Base 2.0.77 recipe-output facts, including raw-level omission, `8000 * 2^(L-1)`, 60-second unit time, exact prerequisite/science multisets, and effect multisets. Factorio does not expose `bool-setting` prototypes to that data stage. The science family has six craftable F200 recipe effects; space science remains a runtime ingredient and prerequisite but is not a F200 recipe output.

Only `recipe-prod-research_gears-1` is accelerated for one real source laboratory completion. The other 30 rows are labelled level seeds, never laboratory evidence. The save records the source gear's +.10 recipe productivity, the independently seeded robot-battery force contribution, foreign queued `.42`, detached `.27`, and the native zero manual-mining baseline. No inventory-capacity source technology is emitted or earned.

The generic native runner must observe two read-only cold reload markers with byte-identical save bytes. A later F200 or F210 successor must consume this protected source save through a separately reviewed fixture and exact package/settings bindings.
