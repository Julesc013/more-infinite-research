# Paired public Library browser fixture

This F200 fixture is a future performance-input witness, not a timing result. It
uses only the historical public `more-infinite-research-browser.open` interface
and native GUI objects; it never imports MIR Lua modules, reads MIR storage,
raises GUI events, completes research, or changes package tuning.

The selected profile enables exactly one arm selector. The selector changes only
the fixture-owned startup setting `mir5-library-paired-browser-arm` before the
ordinary `Defaults` setting mode is read:

| Arm | MIR package | selector | public GUI record |
| --- | --- | --- | --- |
| `published` | 4.7.20002 | `arm-published` | `mir_browser_*` search/results/detail names |
| `mir5` | 5.0.20000 | `arm-mir5` | `mir_library_*` query/results/detail names |

The published arm is pinned to archive `F3943EB4…1010B7`. The candidate arm is pinned to the F200 package from source `8bfb0d99`, archive `2BBDBA9A…F9E842`. These are selected inputs, not matched performance results.

A post-load server emits its one `ready` marker on its first runtime event; the
create-only seed's `on_init` marker is not reused as readiness for the ordinary
host. Each real client join is recorded as the bounded ordered sequence
`MIR5English 1`, `MIR5Deutsch 2`, then after the cold restart `MIR5English 3`,
`MIR5Deutsch 4`. After the first two clients join one fresh Base F200 force,
each of `first-open`, `search`, and `refresh` wraps exactly two public open
calls in one native profiler record, then requests one screenshot per client.
The fixture saves a restart point, requires an actual cold host restart and
rejoin, then performs `reopen` the same way. The original eight immediate PNGs and four raw profiler markers remain. The current diagnostic fixture additionally captures both unchanged first-open roots after 60 ticks, before search, and both unchanged reopened roots after 60 ticks, before completion. These four extra captures occur outside the profiler, without another public open call; native state, query and selected detail are checked again. A replaced or invalid root fails explicitly. Exactly twelve PNGs are now required under `script-output/mir5-library-paired-browser/`, with `first-open-settled` and `reopen-settled` added to the original labels. The shared profiler reader's first action token remains `first_open`. Earlier eight-image datasets retain their original fixture and verdict; the new protocol is a changed diagnostic input requiring its own freeze.

The R01 native performance dataset exposed a missing cold-load readiness witness: the original fixture queued `ready` only for its initial saved world. The current fixture queues exactly one `ready` marker on the first runtime event after either actual load, using local flags only during `on_load`; it still waits for the two new clients and the original settlement delay before reopening. This observation correction qualifies no old missing measurement, changes no player code, and requires its own declared input hash before a replacement native experiment.

At every action boundary it compares a bounded public snapshot of two named
technologies, two recipes, the current research/progress, and an at-most-eight
entry queue. The ordinary fresh seed must have no active or queued research.
These checks show the public browser did not mutate the named native state;
they do not establish live Library refresh, product tuning, screenshot rendering,
process memory, timing acceptance, or a release result. The existing
`library-multiplayer` fixture remains the separate current-candidate functional
scenario with its lab, queue, foreign-force, and ten-capture obligations.
