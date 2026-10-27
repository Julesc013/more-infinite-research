---
title: MIR 1.0.0 F200 migration-origin source fixture
---

This disposable source-only fixture prepares one Factorio 2.0.77 save from the exact public `more-infinite-research` 1.0.0 archive. It is the first direct-F200 origin input for a separately pinned MIR5 successor. It is not a migration pass, a current-package result, or release qualification.

The source package is the official GitHub `1.0.0` release asset `more-infinite-research_1.0.0.zip`, SHA-256 `C328D8F958BEC2A44297E94E83B1A956D76BEA5E333601A42FDDE60F4155472F`, 61,208 bytes. Its tag source is `f0057a96847512b50acdd6e23fc21b5b41e75adb`; the archive is not reconstructed from that source tree.

The fixture checks the source-owned `recipe-prod-research_gears-1` data contract before any fixture acceleration: level one, infinite upgrade, `8000 * 2^(L-1)`, 60 seconds, four one-unit Base science packs, and the +0.10 `iron-gear-wheel` productivity effect. It then reduces only count and time to one for a real source lab completion. Prerequisites are fixture setup only; the named MIR 1.0.0 technology itself is earned by the lab.

The completed source save carries the observed second level and one real source lab completion. The generic native runner must then observe two read-only cold reload markers with byte-identical save bytes. A later current F200 or F210 successor must consume this protected save through its own separately reviewed fixture and exact package binding.
