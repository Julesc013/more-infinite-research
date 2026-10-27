# Space-location API witness

This private fixture observes the Factorio2.1 `LuaForce` space-location methods against the official Space Age `planet-discovery-vulcanus` technology. It records fixture-owned `lock_space_location` then `unlock_space_location` behavior, idempotent duplicate unlock behavior, a still-unresearched location, the native `LuaCustomTable` container shapes, and an unrelated force research-queue sentinel.

It does not earn research, test a MIR migration, perform production work, or establish a gameplay, performance, release, or general persistence claim. The two cold reload checks only read the fixture-owned saved witness.
