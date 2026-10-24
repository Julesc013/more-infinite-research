# Agriculture scale witness

This private F210 2.1.23 fixture has one shared physical agriculture-tower control path. The original scale selectors retain the candidate arm at exactly 1, 32, or 128 towers per force. The paired selectors use that same one-tower physical path with exactly one selected definition arm: the MIR 5 candidate or the published 4.7.21002 package. An arm selector cannot run without the paired selector, and zero or two selected arms refuse before fixture acceleration or world setup.

The candidate arm verifies the enabled infinite twelve-science contract selected by `all-official`, including the promethium prerequisite. The published arm verifies the independently captured 4.7.21002 raw contract: its enabled and hidden fields are omitted, and it has the ordered seven-science prerequisite and ingredient vectors. Those published facts are bound to the F210 capture result `95B1A1FC…67B536C` and raw dump `27FBC90D…7888072`; they are not inferred from the candidate arm. Each arm also verifies its own infinite level, default `40000*1.5^(L-1)` / 90-second tuning, one-percent agricultural effect, and native yumako spoilage contract before only the fixture-world research is accelerated to one unit and one second.

For every selected arm and tier, a real lab completes two agriculture levels. The fixture creates N player towers and N zero-research foreign towers on generated native yumako soil, supplies real yumako seeds, and observes exactly 2N native `on_tower_planted_seed` events. It requires player plants to retain `floor(18000 / 1.01^2)` ticks and foreign plants to retain 18000 ticks. It also records four native yumako spoilage stacks at the unmodified global baseline. The tower/seed insertion profiler is recorded only; it is not a timing result.

The completed world saves as `mir5-native-complete` while plants remain in their native lifecycle. Two cold reloads must preserve research, force, tower-event, plant deadline, and spoil-stack witnesses. `on_load` takes a local read-only snapshot and never repairs storage, technologies, effects, crop timers, or stacks.

The paired fixture gives each arm an honest physical gameplay witness. It does not assert science-vector equality, package parity, ordinary tuning qualification, throughput, or a benchmark result.

## Published source capture

[`agriculture-published-f210-2123.json`](../../../profiles/agriculture-published-f210-2123.json) predeclares the F210 2.1.23 Defaults `--dump-data` capture of published 4.7.21002. Its explicit archive SHA256 is `A4BB8F47232C689B267EF434F557187A8795C47280FA464169DE917FB579517F`; it selects no paired fixture, acceleration, gameplay, save/reload, or benchmark path. The paired published profile carries the recorded archive and observer hashes as independent inputs.
