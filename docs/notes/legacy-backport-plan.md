# Legacy RC Synthesis

Updated: 2026-07-06
Branch: `legacy`
Scope: synthesized planning report for the temporary `tmp/*` Factorio-line branches.

This is a docs-only synthesis of the temporary RC planning sweep. It is a planning
artifact, not a release-candidate approval. Every target still needs actual
target-line implementation work, metadata changes, package construction, and a
matching Factorio binary load test before it can be called stable.

## What Was Done

Each temporary branch now has its own branch-local RC planning report in
`docs/notes` and an updated root `todo.md` checklist on that branch:

| Branch | Target | Planned MIR release slot(s) | Planning commit |
| --- | --- | --- | --- |
| `tmp/2.0` | Factorio `2.0.x` | `1.9.0` trhough `1.9.9` | `9f1db40` | Stable `tmp/2.0` pushed to `legacy` 
| `tmp/1.1` | Factorio `1.1.x` | `1.8.8`, `1.8.9` | `eecfc29` |
| `tmp/1.0` | Factorio `1.0.x` | `1.8.6`, `1.8.7` | `0692099` |
| `tmp/0.17` | Factorio `0.17.x` | `1.8.4`, `1.8.5` | `fe65c21` |
| `tmp/0.16` | Factorio `0.16.x` | `1.8.2`, `1.8.3` | `ce71474` |
| `tmp/0.15` | Factorio `0.15.x` | `1.8.0`, `1.8.1` | `dd04d67` |
| `tmp/0.14` | Factorio `0.14.x` | `1.7.8` | `5e63365` |
| `tmp/0.13` | Factorio `0.13.x` | `1.7.7` | `d9060cb` |
| `tmp/0.12` | Factorio `0.12.x` | `1.7.6` | `c1cacd3` |
| `tmp/0.11` | Factorio `0.11.x` | `1.7.5` | `e615435` |
| `tmp/0.10` | Factorio `0.10.x` | `1.7.4` | `0809e3d` |
| `tmp/0.9` | Factorio `0.9.x` | `1.7.3` | `669bea3` |
| `tmp/0.8` | Factorio `0.8.x` | `1.7.2` | `db3d821` |
| `tmp/0.7` | Factorio `0.7.x` | `1.7.1` | `ec343b8` |
| `tmp/0.6` | Factorio `0.6.x` | `1.7.0` | `b7f27bf` |

## Source Basis

Primary references used across the sweep:

- Official API version index: https://lua-api.factorio.com/
- Mod structure and single-major compatibility rule: https://lua-api.factorio.com/latest/auxiliary/mod-structure.html
- Storage/global runtime split: https://lua-api.factorio.com/latest/auxiliary/storage.html
- Factorio `2.0.77` prototype/runtime docs and JSON: https://lua-api.factorio.com/2.0.77/
- Factorio `1.1.110` prototype/runtime docs and JSON: https://lua-api.factorio.com/1.1.110/
- Factorio `0.12.35` legacy API docs: https://lua-api.factorio.com/0.12.35/
- Wube `factorio-data` prototype history: https://github.com/wube/factorio-data
- FFF #127, source-generated versioned Lua API docs: https://www.factorio.com/blog/post/fff-127
- FFF #141, Mod Portal/licensing/determinism context: https://www.factorio.com/blog/post/fff-141
- FFF #153, `0.13` stable and `0.14` experimental context: https://www.factorio.com/blog/post/fff-153
- FFF #217, `0.16` Lua API additions context: https://www.factorio.com/blog/post/fff-217
- FFF #348, `1.0` GUI/style breaking-change context: https://www.factorio.com/blog/post/fff-348
- FFF #363, `1.1` technology/effect icon context: https://www.factorio.com/blog/post/fff-363
- FFF #53, `0.11` localized-string update context: https://www.factorio.com/blog/post/fff-53
- FFF #3, `0.7.1` Lua API refactoring context: https://www.factorio.com/blog/post/fff-3
- Factorio `0.6.4` stable post: https://direct.factorio.com/blog/post/factorio-0-6-4-is-stable

## Main Conclusion

No target is RC-ready by metadata change alone.

The current MIR source is Factorio `2.1` shaped. It assumes modern metadata,
modern science packs, `storage`, Space Age/Quality/elevated-rails/recycler
surfaces, recipe productivity, modern optional dependency behavior, and runtime
events that do not exist on most target lines. A stable RC requires a real
target-line compatibility implementation for each branch.

## Compatibility Breakpoints

| Line group | Practical interpretation |
| --- | --- |
| `2.0` | Closest target. Keep much of the modern shape, but remove or guard `2.1`-only/unknown surfaces such as the cargo bay unloading distance modifier, lower dependency floors, and validate exact Space Age IDs against `2.0.77`. |
| `1.1`, `1.0`, `0.17` | Reduced modern ports. `max_level` and `count_formula` style infinite technologies are plausible, but `change-recipe-productivity`, Space Age, cargo, and `storage` must be removed or replaced. |
| `0.16`, `0.15` | Old-science infinite ports. `max_level` appears in base data, but science packs use `science-pack-1/2/3`, `high-tech-science-pack`, etc. Current science selection cannot be reused directly. |
| `0.14`, `0.13`, `0.12` | Likely finite-continuation ports. Base data did not show `max_level`/`count_formula`; do not use current infinite-tech generation until a binary proves those fields are accepted. |
| `0.11` through `0.7` | Historical reconstruction. Current API index does not list versioned docs for these lines, so factorio-data plus blog/FFF context and direct binary testing must drive the work. |
| `0.6` | Minimal historical floor. The observed target effects were only gun speed, ammo damage, and inserter stack size. Treat this as a tiny commemorative compatibility release, not MIR parity. |

## Target Recommendations

Start with `tmp/2.0`, then `tmp/1.1`, then `tmp/0.16` or `tmp/0.15` as the first old-science proof. Do not start the `0.14` and older implementation ladder until one finite continuation technology has been proven in a matching old binary.

The safest implementation order is:

1. `tmp/2.0`: close the known cargo modifier and dependency-floor gaps.
2. `tmp/1.1`: prove a reduced no-recipe-productivity modern-science port.
3. `tmp/1.0` and `tmp/0.17`: repeat the reduced modern-science approach.
4. `tmp/0.16` and `tmp/0.15`: build old-science mapping and validate `max_level`.
5. `tmp/0.14`, `tmp/0.13`, `tmp/0.12`: decide finite-chain naming and prove one technology.
6. `tmp/0.11` through `tmp/0.6`: reconstruct only the target-proven native effects.

## Non-Negotiable RC Gates

- The exact MIR `2.x.x` source snapshot must be recorded before each backport.
- `info.json` must be patched to the target line and release version.
- Unsupported modifiers must be removed, not merely hidden behind settings.
- Target science packs and prerequisites must be generated from target-line data.
- Runtime code must use `storage` only on `2.0+`; older runtime work needs `global` or omission.
- Each RC needs a matching Factorio binary load test, or the release notes must explicitly say that binary validation was not run.
- Public notes must say "reduced compatibility subset" where that is the truth.

## Final Read

The campaign is feasible as a celebration/backport ladder only if we accept
progressively smaller feature subsets on older lines. `2.0` can be close to the
current line. `1.1` through `0.15` can probably support useful native infinite
research subsets. `0.14` and older should be treated as finite or historical
ports until direct binary proof says otherwise.
