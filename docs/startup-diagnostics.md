---
title: "Startup diagnostics and retained timing analysis"
status: current
applies_to: "MIR development and support diagnostics"
audience: developer
doc_type: guide
owner: mir-maintainers
last_reviewed: 2026-11-04
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-startup-diagnostics-guidance
---

# Startup diagnostics

This addition reads retained engine logs and existing startup records. It does not instrument ordinary player packages. Begin with observed loader/engine boundaries; internal function durations are unavailable when those boundaries were never recorded. Factorio's loading screen does not expose a documented mod progress-bar API. See the official [libraries](https://lua-api.factorio.com/latest/auxiliary/libraries.html) and [data lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html). `script-output/more-infinite-research/mir.log` remains a support snapshot, with the engine log attached separately.

## Reading an existing log

Run from the repository; output paths must be new and their parent directories must already exist:

```powershell
python -B tools/startup_timings.py --log path/to/factorio-current.log --run-id original-run --json startup-intervals.json --csv startup-intervals.csv
```

Use `--expected-sha256` to require a retained log's exact identity. The reader hashes its input and never launches Factorio, changes settings or overwrites output. JSON contains named interval boundaries, source line numbers, nested phase detail and missing/adverse-boundary issues. CSV includes the six settings/data stage windows, total, missing-boundary warnings and original endpoint identities. Untimestamped output is unavailable; restarted clocks, duplicated phases, crossing pairs and missing ends prevent a scoped total. Nested phases are not added again to whole stages. The post-MIR interval requires a complete final-fixes stage and names its next engine boundary.

Keep three metrics separate:

| Measurement | Meaning and limits |
| --- | --- |
| Process to observed responsive menu | External actor clock and original observation/detection costs; initialization or first render is a different endpoint. |
| Matched MIR-added difference | Same campaign/host/engine/mods/settings/cache policy and endpoint; preserve negative/noisy estimates and uncertainty. No new estimate is derived from a single historical pass. |
| Native scoped or loader intervals | Elapsed time, not exclusive CPU. Loader windows are approximate and can include engine bookkeeping; marker totals use disjoint outer regions. Neither captures every downstream cost caused by MIR. |

Longest observed checkpoint gaps are calculated within each stage, excluding time when other mods run between stages. Missing checkpoints cannot establish a longest actual pause. Post-MIR-to-engine time is named separately and is not assigned to MIR. Printed zero is a rounded observation, not zero cost. No log reader can establish a deadlock, predict arbitrary hardware or replace matched performance testing.

## Retrospective extraction

The [39-row extraction](../spec/evidence/startup-phase-retrospective-aero-r01.csv) retains every original run in [the earlier exploratory snapshot](../spec/evidence/mir5-beta-00-startup-snapshot-r01.json), using its [87-body capsule](../spec/evidence/mir5-beta-00-startup-snapshot-bodies-r01.json.gz). It verifies each consumed raw log/actor byte count and SHA256, reproduces recorded native initialization and actor endpoints, and keeps original package versions, failed menus and missing response measurements. Source commit `125fc7464414dbbe769fee160399e0cb5a9c9eed` identifies the tested MIR5 candidate; these are not published5.0.2 or current-candidate measurements. The snapshot records the actual host, full input identities and original limits.

Reproduce without another game launch:

```powershell
python -B tools/startup_timings.py --snapshot spec/evidence/mir5-beta-00-startup-snapshot-r01.json --bodies spec/evidence/mir5-beta-00-startup-snapshot-bodies-r01.json.gz --json retained-intervals.json --csv retained-intervals.csv
```

The following are sums of MIR loader-message-to-next-loader/engine-boundary windows in individual original runs, in seconds. They are approximate descriptive stage windows, not matched added startup delays or pure Lua durations:

| Original engine/profile | MIR4.7.3 windows | Original MIR5 candidate windows | MIR5 final-fixes window |
| --- | ---: | ---: | ---: |
| 2.0.77 Base | 0.754 | 0.087 | 0.056 |
| 2.0.77 Space Age | 1.007 | 0.143 | 0.112 |
| 2.0.77 heavy Space Age | 2.818 | 0.237 | 0.207 |
| 2.1.23 Base | 0.735 | 0.083 | 0.057 |
| 2.1.23 Space Age | 1.059 | 0.139 | 0.106 |
| 2.1.23 heavy Space Age | 3.070 | 0.300 | 0.258 |

There are no paired internal checkpoints in any of these 39 logs, so internal/scoped time and checkpoint gaps remain unavailable. The last MIR stage in these six candidate runs ends at the first checksum boundary, which can include engine processing. The results locate candidate work around final fixes but cannot identify a slow internal function or prove a pure-script speedup. A separate boundary-only Decimal reader independently reproduced the totals for all39 logs during development; parser controls also retain the adverse heavy-profile menus.

This was an uncontrolled single-pass ordering, with no reboot/cache clear; as-shipped outputs differ. For example, the original2.0 Base no-MIR initialization moved from14.463 to8.989 seconds between its two controls. The2.1 heavy MIR4/MIR5 menu observations failed even though initialization timestamps exist. No causal incremental overhead or new acceptance verdict is inferred. The existing repeated [Base campaign](../spec/evidence/candidate502-base-f200-startup-chain-r01.json) and [earlier heavy campaign](../spec/evidence/f210-current38c-menu-native-chain-r01.json) retain their own matched estimates, packages and uncertainty; these loader windows do not replace or update them.

## Existing controlled comparisons

The same reader extracts [all41 Base runs](../spec/evidence/startup-phase-base-comparison-aero-r01.csv) and [all38 heavy runs](../spec/evidence/startup-phase-heavy-comparison-aero-r01.csv) from their original chain/capsule pairs. It authenticates each capsule against its chain, each consumed log/actor body against its original byte/hash identity, and each confirmed response against the original actor. Warmups and pilots remain separate from scored blocks. Together with the39-run exploratory snapshot this covers118 retained logs, with no new engine launch. None contains the proposed paired internal markers, so scoped execution time and checkpoint gaps remain unavailable throughout.

```powershell
python -B tools/startup_timings.py --comparison spec/evidence/candidate502-base-f200-startup-chain-r01.json --bodies spec/evidence/candidate502-base-f200-startup-receipts-r01.json.gz --json base-intervals.json --csv base-intervals.csv
python -B tools/startup_timings.py --comparison spec/evidence/f210-current38c-menu-native-chain-r01.json --bodies spec/evidence/f210-current38c-menu-native-receipts-r01.json.gz --json heavy-intervals.json --csv heavy-intervals.csv
```

These are the original campaign endpoints and nominal95% intervals, rounded for readability. The actor endpoint was the confirmed responsive Settings screen after a harmless MainMenu click. Added delay is the paired candidate-minus-no-MIR difference; its sign is preserved. Loader windows are a separate descriptive average over the same scored runs and have no causal interpretation:

| Original campaign | Scored runs per arm | No-MIR Settings response | MIR4 Settings response | Candidate Settings response | Candidate added delay and nominal95% interval | MIR4/candidate approximate loader windows |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| 2.0.77 Base | 12 | 10.482s | 11.212s | 10.442s | −0.040s [−0.429,+0.349] | 0.715s /0.078s |
| 2.1.23 heavy Space Age | 8 | 28.695s | 30.925s | 28.322s | −0.373s [−0.905,+0.159] | 2.833s /0.287s |

The Base candidate is source`7fdb1fa63fa6e70a0df437a57765475ba271e8da`, ZIP`6A66CF318AC908788DE24D2E3CD9D8F68421EB8AFDA4C113B2E3012FC701D64F`, not the published5.0.2 ZIP. The earlier heavy candidate is source`992c76ee24caf2d723b469c3db760cbebdf35eeb`; its chain retains the exact archive/profile/engine/settings/controller identities. These are separate experiments, with different candidate packages and declared policies. The original [Base numerical review](../spec/evidence/candidate502-base-f200-startup-numerical-review-aero-r01.json) and heavy chain retain the sampling assumptions, spread, pilot/control checks and limits; the offline extraction neither requalifies them nor transfers their verdicts to another package.

Both candidate-added intervals span zero. A negative point estimate does not establish negative overhead, and no improvement percentage is calculated from that unresolved denominator. The smaller loader windows are evidence about where elapsed time was observed, while startup effects after MIR's stage can remain outside those windows. The absence of internal boundaries prevents attributing final-fixes time to recipe collection versus science, Generator work or other functions. No worthwhile internal bottleneck has been identified by these logs alone; further markers are conditional on an already-needed reproduction.

## Conditional diagnostic markers

If the retained breakdown exposes a worthwhile unresolved interval during an already-needed slow/failing reproduction, the native owner can place a few paired markers around the existing operation in a separate diagnostic copy. Include intended import costs by placing the beginning before those imports. For example:

```lua
log("[MIR startup] stage=data-final-fixes phase=recipe-targets event=begin")
-- Existing operation, unchanged.
log("[MIR startup] stage=data-final-fixes phase=recipe-targets event=end")
```

An optional outer `phase=stage` pair lets the reader retain nested detail without double-counting it. The separate post-MIR metric requires a completed `stage=data-final-fixes phase=stage` pair. The reader also accepts bounded `event=work` checkpoints for observed gaps; it does not derive progress percentages or a total-work denominator. Counters, if needed, must observe an existing pass without per-entry logging or another scan. No diagnostic state or timing decides research output; keep ordinary and instrumented prototype results equal.

Use engine `log()` timestamps, not chat, stdout arrival time or observer receipt time. Untimestamped text remains unavailable. No new clock, profiler assumption, persistent timer, sleep/yield or GUI feature is required; runtime profilers belong to a different stage. Keep normal-package acceptance timings and diagnostic timings distinct. Logging overhead is unmeasured without applicable native evidence, and that diagnostic measurement adds no stable gate. Historical packages and frozen native packets remain unchanged.
