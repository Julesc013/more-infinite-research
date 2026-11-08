---
title: Prepared legacy Settings-search probe
---

# Prepared legacy Settings-search probe

`probe.lua` is a fixed, test-only helper for a later imported/client Library composition. It is not a mod, profile, observer archive, dispatcher, event handler or native/client receipt. Its caller supplies the exact selected player, existing protected-world assertion and current tick, then calls `prepare(stage)`, waits at least the default 30 ticks, and calls `check(stage)`.

The fixed order is `research`, `settings-options-baseline`, `settings-options-repair`, `settings-options-retained-default`, `settings-options-no-match`, `restore-settings-options-empty`, then `restore-research`. The empty baseline and `repair` filter explicitly select the Library’s Other options scope; omitted-tab `default` retains that same scope. Research settings stay covered by the initial independent Research query and must not absorb passive repair. The helper calls the public `more-infinite-research-browser.open` facade, verifies only the owned authored GUI paths, and returns raw query/list/count/tab observations for the caller to capture. It changes the selected player's Library GUI view through that facade, but neither creates a remote interface nor registers events or mutates gameplay research, settings, saves, prototypes or fixture state.

Before use, a separate committed composition must bind this file into an owned archive and retain the exact profile, client roles, protected baseline and client-capture receipt. Passing its host controls prepares that work only; it is not native, rendered-client, release or stable acceptance.
