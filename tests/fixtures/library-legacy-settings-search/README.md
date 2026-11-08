# Prepared legacy Settings-search probe

`probe.lua` is a fixed, test-only helper for a later imported/client Library composition. It is not a mod, profile, observer archive, dispatcher, event handler or native/client receipt. Its caller supplies the exact selected player, existing protected-world assertion and current tick, then calls `prepare(stage)`, waits at least the default 30 ticks, and calls `check(stage)`.

The fixed order is `research`, `settings-baseline`, `settings-repair`, `settings-retained-default`, `settings-no-match`, `restore-research`, then `restore-settings-empty`. The helper calls the public `more-infinite-research-browser.open` facade, verifies only the owned authored GUI paths, and returns raw query/list/count/tab observations for the caller to capture. It neither creates a remote interface nor registers events or mutates research, settings, saves, prototypes or fixture state.

Before use, a separate committed composition must bind this file into an owned archive and retain the exact profile, client roles, protected baseline and client-capture receipt. Passing its host controls prepares that work only; it is not native, rendered-client, release or stable acceptance.
