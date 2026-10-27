---
title: MIR 1.0.0 F200 migration-origin source fixture
---

This disposable source-only fixture prepares one Factorio 2.0.77 save from the exact public `more-infinite-research` 1.0.0 archive. It is the first direct-F200 origin input for a separately pinned MIR5 successor. It is not a migration pass, a current-package result, or release qualification.

The source package is the official GitHub `1.0.0` release asset `more-infinite-research_1.0.0.zip`, SHA-256 `C328D8F958BEC2A44297E94E83B1A956D76BEA5E333601A42FDDE60F4155472F`, 61,208 bytes. Its tag source is `f0057a96847512b50acdd6e23fc21b5b41e75adb`; the archive is not reconstructed from that source tree.

The fixture checks every original F200-emitted `recipe-prod-research_*-1` row before any fixture acceleration. The source roster is sorted from the exact source data stage, has an explicit upper bound of the 31 original MIR1 settings, and retains each row's formula, science multiset and effect vector. It does not assume a current-package roster or a science ordering. Only `recipe-prod-research_gears-1` then has its count and time reduced for one real source lab completion; every other source row is a labelled valid level seed, never a laboratory claim.

The completed source save carries independent player, foreign queued `.42`, and detached `.27` source snapshots for the full observed roster. Snapshots include levels, enablement, saved work, source prototype effects, affected recipe productivity, and an unrelated scripted force offset. The gear row also retains its observed real +.10 productivity contribution. The fixture changes the effective existing `ips-enable-research_breeding` setting to false only because its Space Age source stream is unavailable on F200; the saved setting readback must be carried explicitly by a later successor rather than treating that fixture default change as proof of an arbitrary user override.

The generic native runner must observe two read-only cold reload markers with byte-identical save bytes. A later current F200 or F210 successor must consume this protected save through its own separately reviewed fixture and exact package and setting bindings.
