# Legacy Backport Capability Matrix

Updated: 2026-07-06
Branch: `legacy`
Scope: read-only capability matrix for the temporary legacy backport `tmp/*` branches.

This note materializes the immediate follow-up requested by the read-only RC
audit of the `tmp/x.x` branches. It is a planning artifact only. It does not
certify any branch as a release candidate, and it does not imply that any
branch-local code, metadata, package, or runtime validation has been changed.
Read it as the capability appendix to `docs/notes/legacy-backport-plan.md`.

The important conclusion is unchanged but sharper: every `tmp/*` branch still
needs target-line implementation work before RC naming is honest. The branches
are useful staging branches, not RC branches.

## Status Terms

| Term | Meaning |
| --- | --- |
| `Keep` | The current MIR behavior is plausibly reusable after target metadata and dependency cleanup. |
| `Rewrite` | The target can probably support the feature class, but the modern implementation must be rewritten or heavily adapted. |
| `Cut` | Remove from the first RC for that target line. |
| `Probe` | Official docs or scanned data are not enough; prove the behavior in the matching Factorio binary before implementation claims. |
| `Archive` | Historical compatibility reconstruction, not a true current-line MIR backport. |
| `Museum` | Discovery/artifact branch; implementation scope must be defined from old binaries and old base files before RC planning is meaningful. |
| `Pending` | No target package or binary validation result has been recorded yet. |

## Branch Classification

| Branch | Target Factorio line | Planned MIR slot | Correct release wording | RC posture |
| --- | --- | --- | --- | --- |
| `tmp/2.0` | `2.0.x` | `1.9.7`, `1.9.8`, `1.9.9` | Real backport of a named MIR 2.x source point to Factorio 2.0. | Feasible near-term after moderate cleanup and a 2.0 binary load. |
| `tmp/1.1` | `1.1.x` | `1.8.8`, `1.8.9` | Compatibility port generated from a named MIR 2.x source point. | Not full backport; first serious reduced modern compatibility port. |
| `tmp/1.0` | `1.0.x` | `1.8.6`, `1.8.7` | Compatibility port generated from a named MIR 2.x source point. | Needs a `0.18` bridge decision before heavy investment. |
| `tmp/0.17` | `0.17.x` | `1.8.4`, `1.8.5` | Reduced native-infinite edition. | Plausible old-line native-infinite target after science/effect pruning. |
| `tmp/0.16` | `0.16.x` | `1.8.2`, `1.8.3` | Reduced native-infinite edition. | Needs old science pack mapping and effect whitelist. |
| `tmp/0.15` | `0.15.x` | `1.8.0`, `1.8.1` | Minimal native-infinite edition. | Earliest plausible native-infinite floor; do not overclaim. |
| `tmp/0.14` | `0.14.x` | `1.7.8` | Archive finite-ladder reconstruction. | Not a normal MIR RC until an old binary proves stronger capability. |
| `tmp/0.13` | `0.13.x` | `1.7.7` | Archive finite-ladder reconstruction. | Not a feature-equivalent backport. |
| `tmp/0.12` | `0.12.x` | `1.7.6` | Archive compatibility experiment. | Official API docs exist, but native infinite assumptions are not proven. |
| `tmp/0.11` | `0.11.x` | `1.7.5` | Museum/discovery build. | Define scope from old binaries and base files before RC planning. |
| `tmp/0.10` | `0.10.x` | `1.7.4` | Museum/discovery build. | Define scope from old binaries and base files before RC planning. |
| `tmp/0.9` | `0.9.x` | `1.7.3` | Museum/discovery build. | Define scope from old binaries and base files before RC planning. |
| `tmp/0.8` | `0.8.x` | `1.7.2` | Museum/discovery build. | Define scope from old binaries and base files before RC planning. |
| `tmp/0.7` | `0.7.x` | `1.7.1` | Museum/discovery build. | Define scope from old binaries and base files before RC planning. |
| `tmp/0.6` | `0.6.x` | `1.7.0` | Extreme museum build. | Minimal commemorative floor only. |

## Metadata And Data-Stage Matrix

| Branch | `factorio_version` metadata | Dependency syntax | Settings stage | `data-final-fixes` |
| --- | --- | --- | --- | --- |
| `tmp/2.0` | `Rewrite` to `2.0`; current seed is still modern. | `Rewrite`; remove `2.1` floors and validate optional DLC syntax. | `Rewrite`; prune 2.1-only and unsupported settings. | `Keep` with targeted 2.0 guards. |
| `tmp/1.1` | `Rewrite` to `1.1`. | `Rewrite`; base-era dependency surface only. | `Rewrite`; expose only supported direct-effect settings. | `Rewrite`; reduced generator only. |
| `tmp/1.0` | `Rewrite` to `1.0`. | `Probe`; decide whether a `0.18` artifact can bridge to 1.0. | `Rewrite`; no 2.x or DLC settings. | `Rewrite`; reduced generator only. |
| `tmp/0.17` | `Rewrite` to `0.17`. | `Rewrite`; no modern optional DLC dependencies. | `Rewrite`; keep old-line supported streams only. | `Rewrite`; old-line generator required. |
| `tmp/0.16` | `Rewrite` to `0.16`. | `Rewrite`; old dependency syntax only. | `Rewrite`; old-science settings only. | `Rewrite`; old-line generator required. |
| `tmp/0.15` | `Rewrite` to `0.15`. | `Rewrite`; old dependency syntax only. | `Rewrite`; minimal native-infinite settings only. | `Rewrite`; earliest native-infinite generator only. |
| `tmp/0.14` | `Rewrite` to `0.14`. | `Probe`; old dependency syntax must be verified. | `Cut` modern settings; archive settings only. | `Archive`; finite-ladder or old-binary-proven generator only. |
| `tmp/0.13` | `Rewrite` to `0.13`. | `Probe`; old dependency syntax must be verified. | `Cut` modern settings; archive settings only. | `Archive`; finite-ladder or old-binary-proven generator only. |
| `tmp/0.12` | `Rewrite` to `0.12`. | `Probe`; official docs exist but package behavior still needs binary proof. | `Cut` modern settings; archive settings only. | `Archive`; finite-ladder or old-binary-proven generator only. |
| `tmp/0.11` | `Rewrite` to `0.11`. | `Probe`; no indexed official API docs found in the source sweep. | `Museum`; define after binary archaeology. | `Museum`; current generator is not a candidate. |
| `tmp/0.10` | `Rewrite` to `0.10`. | `Probe`; no indexed official API docs found in the source sweep. | `Museum`; define after binary archaeology. | `Museum`; current generator is not a candidate. |
| `tmp/0.9` | `Rewrite` to `0.9`. | `Probe`; no indexed official API docs found in the source sweep. | `Museum`; define after binary archaeology. | `Museum`; current generator is not a candidate. |
| `tmp/0.8` | `Rewrite` to `0.8`. | `Probe`; no indexed official API docs found in the source sweep. | `Museum`; define after binary archaeology. | `Museum`; current generator is not a candidate. |
| `tmp/0.7` | `Rewrite` to `0.7`. | `Probe`; no indexed official API docs found in the source sweep. | `Museum`; define after binary archaeology. | `Museum`; current generator is not a candidate. |
| `tmp/0.6` | `Rewrite` to `0.6`. | `Probe`; no indexed official API docs found in the source sweep. | `Museum`; define after binary archaeology. | `Museum`; current generator is not a candidate. |

## Technology Capability Matrix

| Branch | Infinite `max_level` | `count_formula` | `change-recipe-productivity` | Lab productivity | Worker robot battery | Cargo modifiers |
| --- | --- | --- | --- | --- | --- | --- |
| `tmp/2.0` | `Keep`; validate against `2.0.77`. | `Keep`; validate formulas in 2.0. | `Keep`; 2.0 docs/data support this class. | `Keep`; 2.0 supports the direct-effect class. | `Probe`; keep only if the 2.0 target accepts the exact modifier. | `Cut/Partial`; keep only proven 2.0 modifiers and remove unknown 2.1-only cargo surfaces. |
| `tmp/1.1` | `Keep`. | `Keep`. | `Cut`; not proven in the 1.1 source sweep. | `Keep`; 1.1 docs/data support this class. | `Keep`; 1.1 docs/data support this class. | `Cut`; cargo platform/landing-pad modifiers are 2.x-era. |
| `tmp/1.0` | `Keep/Probe`; base data shows infinite-style fields, binary proof still required. | `Keep/Probe`. | `Cut`. | `Probe`; cut if the 1.0 binary rejects it. | `Probe`; cut if the 1.0 binary rejects it. | `Cut`. |
| `tmp/0.17` | `Keep/Probe`; base data shows infinite-style fields, binary proof still required. | `Keep/Probe`. | `Cut`. | `Probe`; cut if the 0.17 binary rejects it. | `Probe`; cut if the 0.17 binary rejects it. | `Cut`. |
| `tmp/0.16` | `Keep/Probe`; old-science native infinite port is plausible. | `Keep/Probe`. | `Cut`. | `Probe/Cut`; do not ship unless proven. | `Probe/Cut`; do not ship unless proven. | `Cut`. |
| `tmp/0.15` | `Keep/Probe`; earliest native-infinite floor. | `Keep/Probe`. | `Cut`. | `Probe/Cut`; do not ship unless proven. | `Probe/Cut`; do not ship unless proven. | `Cut`. |
| `tmp/0.14` | `Probe`; assume no for first archive RC. | `Probe`; assume no for first archive RC. | `Cut`. | `Cut`. | `Probe/Cut`; only if old data and binary prove it. | `Cut`. |
| `tmp/0.13` | `Probe`; assume no for first archive RC. | `Probe`; assume no for first archive RC. | `Cut`. | `Cut`. | `Probe/Cut`; only if old data and binary prove it. | `Cut`. |
| `tmp/0.12` | `Probe`; official docs exist, but no current infinite assumption. | `Probe`; assume no for first archive RC. | `Cut`. | `Cut`. | `Probe/Cut`; only if old data and binary prove it. | `Cut`. |
| `tmp/0.11` | `Museum`; define from old binary behavior. | `Museum`; define from old binary behavior. | `Cut`. | `Cut`. | `Museum`; define from old data. | `Cut`. |
| `tmp/0.10` | `Museum`; define from old binary behavior. | `Museum`; define from old binary behavior. | `Cut`. | `Cut`. | `Museum`; define from old data. | `Cut`. |
| `tmp/0.9` | `Museum`; define from old binary behavior. | `Museum`; define from old binary behavior. | `Cut`. | `Cut`. | `Museum`; define from old data. | `Cut`. |
| `tmp/0.8` | `Museum`; define from old binary behavior. | `Museum`; define from old binary behavior. | `Cut`. | `Cut`. | `Museum`; define from old data. | `Cut`. |
| `tmp/0.7` | `Museum`; define from old binary behavior. | `Museum`; define from old binary behavior. | `Cut`. | `Cut`. | `Museum`; define from old data. | `Cut`. |
| `tmp/0.6` | `Museum`; likely no native infinite edition. | `Museum`; likely no native infinite edition. | `Cut`. | `Cut`. | `Cut`; not a first-pass feature. | `Cut`. |

## Prototype, Runtime, And Validation Matrix

| Branch | Science pack names | Recipe result schema | Icon schema | Runtime events | Migrations | Package validation | Binary load result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `tmp/2.0` | Modern 2.0 names; validate Space Age IDs against 2.0. | `Rewrite check`; 2.0 uses modern recipe prototype fields and category rules. | `Keep/Probe`; remove 2.1 assumptions. | `Keep`; use `storage`, but validate every event. | `Rewrite/Validate`; JSON migration set must match target names. | `Pending`. | `Pending`. |
| `tmp/1.1` | Modern non-Space-Age names. | `Rewrite`; old normal/expensive/result variants must be supported. | `Probe`; validate icon fields and effect icons. | `Rewrite`; use `global`, not `storage`; no 2.x events. | `Probe/Validate`; only target-supported migrations. | `Pending`. | `Pending`. |
| `tmp/1.0` | Modern non-Space-Age names. | `Rewrite`; old normal/expensive/result variants must be supported. | `Probe`; validate icon fields and effect icons. | `Rewrite`; use `global`, not `storage`; no 2.x events. | `Probe/Validate`; only target-supported migrations. | `Pending`. | `Pending`. |
| `tmp/0.17` | Modern science pack names, no Space Age. | `Rewrite`; old result forms and category assumptions must be checked. | `Probe`; validate icon fields and effect icons. | `Rewrite`; use `global`, not `storage`; no 2.x events. | `Probe/Validate`; only target-supported migrations. | `Pending`. | `Pending`. |
| `tmp/0.16` | Old names: `science-pack-1/2/3`, military, production, high-tech, space. | `Rewrite`; old result forms and category assumptions must be checked. | `Probe`; old icon stack behavior must be validated. | `Rewrite`; use `global`, not `storage`; old event whitelist only. | `Probe/Validate`; only target-supported migrations. | `Pending`. | `Pending`. |
| `tmp/0.15` | Old names: `science-pack-1/2/3`, military, production, high-tech, space. | `Rewrite`; old result forms and category assumptions must be checked. | `Probe`; old icon stack behavior must be validated. | `Rewrite`; use `global`, not `storage`; old event whitelist only. | `Probe/Validate`; only target-supported migrations. | `Pending`. | `Pending`. |
| `tmp/0.14` | Alien-era old science names. | `Archive`; construct from target base files. | `Archive`; old icon shape only. | `Archive/Probe`; old event whitelist only. | `Probe`; possibly omit for first archive build. | `Pending`. | `Pending`. |
| `tmp/0.13` | Alien-era old science names. | `Archive`; construct from target base files. | `Archive`; old icon shape only. | `Archive/Probe`; old event whitelist only. | `Probe`; possibly omit for first archive build. | `Pending`. | `Pending`. |
| `tmp/0.12` | Alien-era old science names. | `Archive`; construct from target base files and 0.12 docs. | `Archive`; old icon shape only. | `Archive/Probe`; 0.12 official docs exist, but no modern runtime assumptions. | `Probe`; possibly omit for first archive build. | `Pending`. | `Pending`. |
| `tmp/0.11` | Alien-era old science names. | `Museum`; construct from old base files. | `Museum`; construct from old base files. | `Museum`; rely on old binary/API archaeology. | `Museum`; likely omit unless proven. | `Pending`. | `Pending`. |
| `tmp/0.10` | Alien-era old science names. | `Museum`; construct from old base files. | `Museum`; construct from old base files. | `Museum`; rely on old binary/API archaeology. | `Museum`; likely omit unless proven. | `Pending`. | `Pending`. |
| `tmp/0.9` | Alien-era old science names. | `Museum`; construct from old base files. | `Museum`; construct from old base files. | `Museum`; rely on old binary/API archaeology. | `Museum`; likely omit unless proven. | `Pending`. | `Pending`. |
| `tmp/0.8` | Alien-era old science names. | `Museum`; construct from old base files; recipe shape appears especially different. | `Museum`; construct from old base files. | `Museum`; rely on old binary/API archaeology. | `Museum`; likely omit unless proven. | `Pending`. | `Pending`. |
| `tmp/0.7` | Alien-era old science names. | `Museum`; construct from old base files. | `Museum`; construct from old base files. | `Museum`; rely on old binary/API archaeology. | `Museum`; likely omit unless proven. | `Pending`. | `Pending`. |
| `tmp/0.6` | Early old science names only. | `Museum`; construct from old base files. | `Museum`; construct from old base files. | `Museum`; rely on old binary/API archaeology. | `Museum`; likely omit. | `Pending`. | `Pending`. |

## First RC Feature Policy

| Line group | First RC policy |
| --- | --- |
| `2.0` | Preserve the largest feature set, but remove or guard `2.1`-only surfaces and prove exact 2.0 Space Age behavior. |
| `1.1`, `1.0` | Ship a compatibility port with modern non-Space-Age science, direct-effect whitelists, no recipe productivity unless target proof appears, no cargo, no DLC surfaces, and `global` runtime state. |
| `0.17` | Treat as the first old-line native-infinite port; keep only effects proven by 0.17. |
| `0.16`, `0.15` | Treat as old-science native-infinite editions; science names and formula behavior are the primary gates. |
| `0.14`, `0.13`, `0.12` | Treat as archive finite-ladder reconstructions unless a matching binary proves native infinite support. |
| `0.11` through `0.7` | Treat as museum/discovery builds. Start from target base files, old blog/FFF evidence, and binary behavior. |
| `0.6` | Treat as a minimal commemorative museum build; likely only ammo damage, gun speed, and inserter stack size are viable first-pass concepts. |

## Consolidated RC Gates

No branch should be called RC until all of these are true for that branch:

- `info.json` has the intended MIR release version and matching `factorio_version`.
- Dependency syntax and optional dependency names are valid for the target Factorio line.
- Unsupported modern streams are removed from settings, defaults, generation, locale, docs, and release notes.
- Every generated technology uses target-valid science pack names.
- Every generated effect type is accepted by the target binary.
- Every recipe/productivity stream uses the target recipe prototype shape.
- Runtime code is either removed or uses the target runtime persistence model.
- Migrations are either proven valid for the target line or intentionally omitted.
- A package has been built with the target branch contents, not with a mixed checkout.
- The package has been loaded by the matching Factorio binary.
- Release notes use the correct wording: backport, compatibility port, reduced native-infinite edition, archive reconstruction, or museum build.

## Recommended Order

1. Finish `tmp/2.0` first. It is the only near-term real backport candidate.
2. Use `tmp/1.1` as the first reduced compatibility-port proof.
3. Decide whether a `0.18` bridge artifact can reduce or replace separate `tmp/1.0` work.
4. Use `tmp/0.17` as the first old-line native-infinite proof.
5. Use `tmp/0.16` and `tmp/0.15` to prove old-science native-infinite generation.
6. Defer `tmp/0.14` and older until the archive/museum scope is explicitly accepted.

## Source Basis

This matrix synthesizes the branch-local RC planning notes, the attached
read-only RC audit, official Factorio Lua API documentation, scanned
`wube/factorio-data` history, and historical Factorio blog/FFF posts already
listed in `legacy-backport-plan.md`.

Key external references:

- Official API version index: https://lua-api.factorio.com/
- Factorio `2.0.77` docs: https://lua-api.factorio.com/2.0.77/
- Factorio `1.1.110` docs: https://lua-api.factorio.com/1.1.110/
- Factorio `0.12.35` docs: https://lua-api.factorio.com/0.12.35/
- Mod structure and single-major compatibility rule: https://lua-api.factorio.com/2.0.77/auxiliary/mod-structure.html
- Wube `factorio-data` history: https://github.com/wube/factorio-data
- Factorio `0.15.0` release note basis for native infinite research boundary: https://store.steampowered.com/news/posts/?appids=427520&enddate=1493217030
