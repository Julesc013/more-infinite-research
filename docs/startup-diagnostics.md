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

The engine log carries a small fixed set of `[MIR startup]` phase boundaries for settings, data and final fixes. Final fixes separate settings/repairs, catalogue construction, recipe targeting, materials/science, publication and optional overrides. The seven stable historical subsets use their reduced entrypoints with the same stage boundaries and their applicable phases. Early best-effort packages can replace entrypoints and have no complete-observability claim. The helper's own import precedes its first marker; later imports inside marked regions are included. A failed operation leaves its region incomplete.

The existing `mir-debug-generation-report` option adds recipe counts every 4,096 visited recipes, up to eight intermediate messages and one final count. It uses the collector's existing work, adds no denominator pass and reports candidate binding matches separately from accepted family/recipe targets. Counts at intermediate checkpoints depend on traversal order; final output remains deterministic. The new helper allows at most 48 messages per stage instance; existing diagnostic messages, especially the separate recipe-match option, retain their own behavior and are outside this budget. A failed diagnostic transport is ignored by this helper, while product errors still propagate. No persistent state, timer, prototype mutation or new setting is involved.

Factorio supplies native timestamps to `log()`. On engines lacking that function, a checked `print()` fallback can convey phase text without a native timestamp; the reader leaves those intervals unavailable. There is no documented mod loading-bar API here, and no attempt to yield, sleep or move prototype construction to runtime. See the official [libraries](https://lua-api.factorio.com/latest/auxiliary/libraries.html) and [data lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html). `script-output/more-infinite-research/mir.log` remains a support snapshot, with the engine log attached separately.

## Reading an existing log

Run from the repository; output paths must be new and their parent directories must already exist:

```powershell
python -B tools/startup_timings.py --log path/to/factorio-current.log --run-id original-run --json startup-intervals.json --csv startup-intervals.csv
```

Use `--expected-sha256` to require a retained log's exact identity. The reader hashes its input and never launches Factorio, changes settings or overwrites output. JSON contains named interval boundaries, source line numbers, nested phase detail and missing/adverse-boundary issues. CSV is a compact summary. Untimestamped output is unavailable; restarted clocks, duplicated phases, crossing pairs and missing ends prevent a scoped total. Nested phases are not added again to whole stages. The post-MIR interval requires a complete final-fixes stage and names its next engine boundary.

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

The new markers have host output-equivalence controls, including transport failure and a one-pass bounded recipe counter. Their elapsed logging overhead and rendered loading experience are unmeasured until applicable native evidence exists. They add no new stable gate and do not alter any frozen native packet or previously published package.
