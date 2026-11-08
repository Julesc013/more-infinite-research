---
title: "Worker storage native regression observer"
status: current
applies_to: "Factorio 2.1.24 synthetic worker continuation check"
audience: developer
doc_type: test-fixture
owner: mir-maintainers
last_reviewed: 2026-11-08
supersedes: []
superseded_by: []
---

# Worker storage native regression observer

This fixture observes the separate `worker-storage-finite-provider` fixture. It does not reproduce the unnamed planet in the public report. Package only `info.json`, `data.lua`, and `control.lua` under `mir-worker-storage-native-observer_0.1.2/`; documentation is outside the fixture archive.

The source profile uses the genuine published F210 MIR 4.7.3 package, Factorio 2.1.24, the finite provider 0.1.0, this observer 0.1.2, and Base only. The candidate profile changes only the MIR archive. Keep the exact provider and observer versions unchanged so that the migration tests the actual MIR transition.

## What the fixture proves

The fixture seeds science prerequisites and native worker-storage levels 1 through 4. Their carrying-capacity baseline is five. It creates an actual lab, supplies its real science ingredients and energy, and accelerates lab speed. It does not change the MIR research count, time, or effects and does not grant a MIR level by script; its research completion handler rejects `by_script=true`.

After each native lab completion the expected carrying-capacity bonus is `5 + 2 * completion_count`. The fixture deliberately sets current work to 42% and unrelated saved work to 27%, then queues the worker continuation before the unrelated probe. These are continuity sentinels, not evidence that those partial fractions were earned by science consumption.

| Mode | Expected input | Observation |
|---|---|---|
| `source` | Fresh original MIR 4.7.3 seed, zero MIR completions | Earn one level through a lab, preserve the foreign finite owner, and create `worker-source.zip`. |
| `successor` | The exact source save with one completion | Require the same earned capacity, partial work and queue before earning a second level; create `worker-successor.zip`. |
| `fresh` | Fresh candidate seed | Earn one level through a lab and create `worker-fresh.zip`. |
| `reload` | A completed source or successor save | Read and assert the saved state without granting research or creating another save. |

## Execution and custody

Create the seed with the normal `--create` entry point. Use an isolated headless server with public and LAN visibility disabled, `auto_pause=false`, a localhost bind, and an existing writable `saves` directory. Supply the full official server-settings template with those overrides. Start a mode through the fixture's explicit test interface: `remote.call("mir-worker-storage-native-observer", "begin", "source")`. The first Lua console command may require the normal Factorio confirmation; repeat it only when that warning is observed.

Always give the server a disposable byte-for-byte copy of the protected input save. A normal SIGINT shutdown writes the running map back to its input path. Verify the protected original's SHA256 before and after execution and retain the exact output save separately.

Accept an earning leg only when the engine emits the corresponding `*-finished.json`, the named output ZIP is complete, and the log confirms the save. Exit code zero alone does not prove completion. The observer writes bounded facts under `script-output/worker-storage/` and the log prefix `MIR_WORKER_NATIVE`.

For cold reloads, start two separate `--test-save` processes with `--test-arg reload`. Require the observer's reload record, an explicit engine `Test passed` message, preserved sentinels and the same protected input hash after both processes. `--test-ticks` expiry by itself is not a pass. On the observed 2.1.24 test runner, `game.auto_save` did not produce the earning save; use the server leg for the protected source and successor instead.

The native reassessment receipt records exact archive hashes, commands, observations, source provenance, and adverse harness attempts. This fixture does not establish Space Is Fake integration, Factorio 2.0 execution, an actual reporter mod pack, client UI behavior, multiplayer synchronization, or performance qualification.
