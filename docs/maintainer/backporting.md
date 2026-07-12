---
title: "Target-Line Versioning And Backports"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---
# Target-Line Versioning And Backports

Updated: 2026-07-12

## Current 3.1 Release Roles

Published MIR `3.0.5` on the Factorio 2.1 line and MIR `2.3.5` on `legacy` are immutable. Automatic-compiler work is unreleased MIR `3.1.0` on `dev`; its Factorio 2.0 semantic companion will be unreleased MIR `2.4.0` on `tmp/2.0` only after the modern implementation passes. Earlier 3.1.0 and 2.4.0 candidate commits, tags, and archives are superseded development evidence and are not publication authority.

The current older-target state is MIR `1.9.4` qualified but unreleased on `tmp/1.1`, MIR `1.8.2` staged but runtime-unqualified on `tmp/1.0`, MIR `1.7.1` planned on `tmp/0.17`, MIR `1.6.0` planned on `tmp/0.16`, and MIR `1.5.0` planned on `tmp/0.15`. Archived plans retain their historical version numbers; current 0.16 and 0.15 work follows the new 1.6.0 and 1.5.0 plans.

This note records the locked maintainer policy for separating MIR release numbers by Factorio target line after the `2.2.0` compatibility-platform release. It is a release-operations note, not a feature-parity promise. Every target line still needs its own source branch, metadata, package build, Factorio binary, mod library, validation artifacts, and public release notes before it can be published.

Factorio `0.17` completed that gate on 2026-07-10. MIR `1.7.0` was published from commit `1a9b5a7b1162f8dca8125ef7bb792f57a9ae282b` and tag `1.7.0` using the exact archive recorded in `.mir/branches.yml`. Its portable prerequisite and graph-safety lessons are inputs to the `3.0.5` convergence phase; its metadata, reduced feature surface, `global` runtime backend, and target-era assets remain local to the Factorio `0.17` line.

## Current Transition State

The `2.2.0` release was cut under the old numbering scheme, where the active `2.x.x` MIR line targeted Factorio `2.1`. After the `2.2.0` release and its Factorio `2.0` backport are complete, MIR moves to a locked target-line numbering scheme. Public MIR version numbers now encode the target Factorio generation. They no longer only encode MIR's internal architecture generation.

| MIR version range | Factorio target line | First planned release in range | Support class | Notes |
| --- | --- | --- | --- | --- |
| `3.x.x` | Factorio `2.1` | `3.0.5` | Canonical modern | Compatibility-hardening candidate from the 3.0.0 source anchor. |
| `2.x.x` | Factorio `2.0` | `2.3.0` | Maintained `2.0` backport | First post-3.0 port of the compiler architecture. |
| `1.9.x` | Factorio `1.1` | `1.9.3` | Compatibility port | `1.9.0` through `1.9.2` are transition exceptions for Factorio `2.0`. |
| `1.8.x` | Factorio `0.18` bridge / `1.0` | `1.8.0` / `1.8.1` | Bridge archive / compatibility port | `1.8.0` is the one-time `0.18` bridge exception; `1.8.1+` is the maintained `1.0` line. |
| `1.7.x` | Factorio `0.17` | `1.7.0` | Reduced native-infinite | First old-line native-infinite target. |
| `1.6.x` | Factorio `0.16` | `1.6.0` | Old-science native-infinite | Requires old science-pack mapping. |
| `1.5.x` | Factorio `0.15` | `1.5.0` | Minimal native-infinite | Earliest plausible native-infinite floor. |
| `1.4.x` | Factorio `0.14` | `1.4.0` | Archive finite reconstruction | Not full MIR parity. |
| `1.3.x` | Factorio `0.13` | `1.3.0` | Archive finite reconstruction | Not full MIR parity. |
| `0.12.x` | Factorio `0.12` | `0.12.0` | Archive experiment | Official docs exist, but native infinite support is not assumed. |
| `0.11.x` | Factorio `0.11` | `0.11.0` | Museum/discovery | Define from old binary and base files. |
| `0.10.x` | Factorio `0.10` | `0.10.0` | Museum/discovery | Define from old binary and base files. |
| `0.9.x` | Factorio `0.9` | `0.9.0` | Museum/discovery | Define from old binary and base files. |
| `0.8.x` | Factorio `0.8` | `0.8.0` | Museum/discovery | Define from old binary and base files. |
| `0.7.x` | Factorio `0.7` | `0.7.0` | Museum/discovery | Define from old binary and base files. |
| `0.6.x` | Factorio `0.6` | `0.6.0` | Extreme museum | Minimal commemorative compatibility floor. |

The awkward part is intentional and must be documented in release notes: `1.9.0`, `1.9.1`, and `1.9.2` are historical Factorio `2.0` transition backports. Starting at `1.9.3`, the `1.9.x` range is reserved for Factorio `1.1`.

The transition rule is:

```text
Legacy mapping era:
  1.9.0 through 1.9.2 target Factorio 2.0.

Target-line mapping era:
  1.9.3 and later target Factorio 1.1.
  2.x.x targets Factorio 2.0 starting at 2.3.0.
  3.x.x targets Factorio 2.1 starting at 3.0.0.
```

The `1.8.x` range has one deliberate bridge exception:

```text
1.8.0 targets Factorio 0.18 as a frozen bridge/archive package.
1.8.1 and later target Factorio 1.0 as the maintained support line.
0.8.x remains reserved for Factorio 0.8 museum/discovery builds.
```

Do not use `0.8.1` or any other `0.8.x` release number for Factorio `1.0`. That range belongs to the later Factorio `0.8` museum line.

## Branch Roles

Use these branch roles during the transition:

| Branch or worktree | Role | New release line |
| --- | --- | ---: |
| `main` | Stable canonical Factorio `2.1` line after gates. | `3.x.x` after `3.0.0` |
| `dev` | Development canonical Factorio `2.1` line. | `3.x.x` after `3.0.0` |
| `legacy` | Frozen Factorio `2.0` MIR `2.3.x` stable baseline. | No new feature releases. |
| `tmp/2.0` | Maintained Factorio `2.0` semantic companion branch after 3.1.0 acceptance. | Unreleased `2.4.0` from frozen `2.3.5`. |
| `tmp/1.1` | Working Factorio `1.1` port branch or worktree. | `1.9.x` starting at `1.9.3` |
| `port/1.1-to-0.18` | Short-lived Factorio `0.18` bridge branch seeded from the validated `1.9.3` source point. | `1.8.0` only |
| `tmp/1.0` | Working Factorio `1.0` port branch or worktree after the `0.18` bridge proof. | `1.8.1+` |
| `tmp/0.17` | Working Factorio `0.17` port branch or worktree. | `1.7.x` |
| `tmp/0.16` | Working Factorio `0.16` port branch or worktree. | `1.6.x` |
| `tmp/0.15` | Working Factorio `0.15` port branch or worktree. | `1.5.x` |
| `tmp/0.14` | Working Factorio `0.14` port branch or worktree. | `1.4.x` |
| `tmp/0.13` | Working Factorio `0.13` port branch or worktree. | `1.3.x` |
| `tmp/0.12` | Working Factorio `0.12` port branch or worktree. | `0.12.x` |
| `tmp/0.11` | Working Factorio `0.11` port branch or worktree. | `0.11.x` |
| `tmp/0.10` | Working Factorio `0.10` port branch or worktree. | `0.10.x` |
| `tmp/0.9` | Working Factorio `0.9` port branch or worktree. | `0.9.x` |
| `tmp/0.8` | Working Factorio `0.8` port branch or worktree. | `0.8.x` |
| `tmp/0.7` | Working Factorio `0.7` port branch or worktree. | `0.7.x` |
| `tmp/0.6` | Working Factorio `0.6` port branch or worktree. | `0.6.x` |

`tmp/*` branches should be treated as disposable validation workspaces. They can carry target-line metadata, API removals, and diagnostic experiments while the port is being proven. Durable fixes discovered there should be cherry-picked or ported back to `dev`, but target-line metadata downgrades should not be merged back into the current line.

For safer local work, prefer `git worktree` checkouts for `tmp/*` branches so a Factorio `2.0` port can be validated while `dev` remains available for Factorio `2.1` fixes.

Target capability classifications are centralized in `.mir/targets.json`. After retargeting `info.json` on a branch, run `.\scripts\Sync-MIRTargetProfiles.ps1` and commit the generated Lua view. PowerShell gates read the same manifest directly, and architecture validation rejects drift between the manifest, generated Lua, and current metadata.

## Immediate `2.2.0` To `1.9.2` Flow

The immediate transition plan is:

1. Install a real Factorio `2.0` Space Age-capable binary at `D:\Programs\Factorio`.
2. Create `tmp/2.0` from the validated `2.2.0` source point.
3. Change the backport metadata for Factorio `2.0`:
   - `info.json` version becomes `1.9.2`;
   - `factorio_version` becomes `2.0`;
   - base dependency floor becomes `base >= 2.0`;
   - official optional dependencies must not carry Factorio `2.1` floors.
4. Remove or guard Factorio `2.1`-only prototype surfaces, especially cargo landing-pad and cargo unloading direct modifiers unless Factorio `2.0` validation proves they load.
5. Run the Factorio `2.0` validation lane from `tmp/2.0`:

   ```powershell
   .\scripts\Invoke-MIRValidation.ps1 -StaticOnly
   .\scripts\Invoke-MIRValidation.ps1 -FactorioBin 'D:\Programs\Factorio\bin\x64\factorio.exe'
   .\scripts\mir.ps1 release gate --profile release-targeted-2.0 --factorio 'D:\Programs\Factorio\bin\x64\factorio.exe' --mods 'C:\Projects\Factorio\testmods_2.0' --no-git-pull
   ```

6. Bring portable bug fixes and validation-tool fixes from `tmp/2.0` back to `dev`.
7. Revalidate `dev` on the Factorio `2.1` Steam install:

   ```powershell
   .\scripts\Invoke-MIRValidation.ps1 -FactorioBin 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
   .\scripts\mir.ps1 release gate --profile release-targeted-2.1 --no-git-pull
   ```

8. Publish the current-line release from `main` after `dev` is fast-forwarded and the release gate passes.
9. Merge or fast-forward the validated `tmp/2.0` port into `legacy` for the `1.9.2` release.
10. After `1.9.2`, return durable process/docs/tooling improvements to `dev`
    and begin the `3.0.0` architecture line.

As of 2026-07-07, the `2.2.0` current-line release gate, package upload, and `main` push are complete. Treat `dist/more-infinite-research_2.2.0.zip` as a published immutable archive, not a live package-parity artifact for later `dev` commits. The same rule applies to the `legacy` branch once `dist/more-infinite-research_1.9.2.zip` is uploaded.

Post-`2.2.0` source work targets `3.0.0` on the Factorio `2.1` line. The planned target-line ports are `2.3.0` for Factorio `2.0` and `1.9.3` for Factorio `1.1`. If a validation command rebuilds a published `2.2.0` or `1.9.2` archive while testing later source work, restore the published archive instead of committing the rebuild.

## `3.0.0` Charter

`3.0.0` should not be framed as "more productivity technologies." It should be the Factorio `2.1` compatibility-compiler release:

```text
discover prototypes
normalize facts
resolve capabilities
classify families and risks
propose candidate ownership
validate owner, lab, cap, graph, and policy gates
emit through validated StreamSpecs
observe unknown or risky cases through diagnostics
fixture-test the result
```

The 3.0 line should formalize:

- capability resolver contracts;
- schema-versioned facts, candidates, decisions, stream specs, manifests, and compatibility claims;
- one-way module boundaries where `emit/` is the only layer that mutates prototypes;
- policy overlays instead of mod-specific behavior scripts;
- stable generated technology IDs and migration rules;
- negative fixtures for loop-risk, hidden, cap-zero, external-owner, science, loader-like, and drill-like decoys;
- differential planner report tooling;
- performance budgets for large compatibility targets;
- public ADRs for architecture, settings, migration, claims, and runtime boundaries.

`3.0.0` can use existing proof surfaces such as Air Scrubbing, ATAN Ash, ATAN Nuclear Science, AAI Loaders, Big Mining Drill, and the requested local load checks, but it should not become a broad K2/Bob/Angel/SE/Py generation release. The detailed 3.0 architecture charter lives in `docs/architecture/compatibility-compiler-charter.md`.

## Backporting `3.0.0`

Once `3.0.0` is stable on the Factorio `2.1` line:

1. Create target-line `tmp/*` branches or worktrees from the tested `3.0.0` source point.
2. Apply target-line metadata and API guards.
3. Run the matching binary and local mod-library validation for each line.
4. Bring portable fixes back to `dev`.
5. Publish only target lines that pass their own validation.

Current execution state:

- The `3.0.0` source anchor is commit `8da631a6e5774af6d8804a49107a61a7964a5b2c` on `main`, with package `dist/more-infinite-research_3.0.0.zip`.
- The `3.0.0` package SHA-256 is `E9A644468217D6B8B07F30E92179BE7BB2DFE951A14F211C1E924A5A505ECCDC`.
- Fast-forward `dev` to the validated `main` anchor before starting target-line ports.
- Merge or snapshot `dev` into `tmp/2.0`, then apply Factorio `2.0` metadata, API guards, release docs, package rebuild, and validation for `2.3.0`.
- Merge or fast-forward `tmp/2.0` into `legacy` only after the `2.3.0` package loads on a real Factorio `2.0` binary and the release docs match the branch.
- Release older lines from their own `tmp/*` or stable target branches in descending order, using the target-line matrix below and the historical cadence note as the release order guide.
- After each backport ring, bring portable fixes, tests, documentation, and tooling lessons back to `dev`, but do not cut an immediate `3.0.1` release.
- Keep `dev` as the accumulating Factorio `2.1` integration branch while the `3.0.0` backport rings are worked.
- The automated `3.0.5` candidate gate is complete after the published 2.0, 1.1, 1.0, 0.18, and 0.17 lines produced portable lessons. Publication still requires manual acceptance of the exact archive. Target-line metadata downgrades remain excluded from `dev`.
- Start `3.1.0` only after the `3.0.5` learning patch is stable. Treat `3.1.0` as the fixture-backed overhaul support campaign, not as cleanup from the backport ladder.

Backports from `3.0.0` should preserve the compiler architecture only where the target Factorio line can support it. Do not describe this as backporting `3.0.0` wholesale to every `tmp/*` branch. The correct policy is:

```text
Port the MIR 3 architecture downward branch by branch.
Older Factorio lines receive only the subset their API and binary validation
can support.
```

Expected degradation by target line:

| Target | Compiler posture |
| --- | --- |
| Factorio `2.1` | Full compiler architecture. |
| Factorio `2.0` | Most compiler architecture with `2.1`-only surfaces disabled. |
| Factorio `1.1` / `1.0` | Reduced compiler architecture, direct-effect and science/lab planner only unless more is proven. |
| Factorio `0.17` / `0.16` / `0.15` | Minimal compiler architecture with old-science native-infinite subset. |
| Factorio `0.14` / `0.13` / `0.12` | Finite-ladder compiler mode only if binary proof allows. |
| Factorio `0.11` through `0.6` | Museum compiler mode or hand-authored historical reconstruction. |

If an older line cannot support a surface, the port should remove, disable, or report that surface and document the exclusion rather than simulating feature parity with unsafe runtime behavior.

## Backport Rings

Use rings, not a waterfall. Do not flow constraints from a lower target line back into higher lines as inherited architecture.

The source of truth for every ring is the `3.0.0` source anchor plus portable fixes deliberately brought back to `dev`. Lower target branches must not inherit from each other unless a change is explicitly target-line local and already validated for that line.

| Ring | Target | Rule |
| --- | --- | --- |
| 1 | Factorio `2.0` | Port from `3.0.0`; remove or disable Factorio `2.1` surfaces. |
| 2 | Factorio `1.1` | Reduced port from `3.0.0` plus portable `2.0` lessons. |
| 3 | Factorio `0.18` bridge and Factorio `1.0` | Build `1.8.0` as the bridge/archive proof from `1.9.3`, then establish `1.8.1+` as the maintained `1.0` line. |
| 4 | Factorio `0.17` / `0.16` / `0.15` | Native-infinite subsets only after binary proof. |
| 5 | Factorio `0.14` / `0.13` / `0.12` | Archive finite-ladder packages unless binary proof supports more. |
| 6 | Factorio `0.11` through `0.6` | Museum/discovery builds defined from matching binaries and base files. |

Each ring can send portable improvements back to `dev`: validation script improvements, target manifest fixes, report diff fixes, package hygiene fixes, docs corrections, generic platform-adapter fixes, clearer errors, and deterministic ordering fixes. These returns accumulate on `dev`; they are not a reason to cut `3.0.1` while the backport ladder is still active.

Target-line edits must stay out of `dev`: `factorio_version = "2.0"` or older, lower `base` dependency floors, removed `2.1` dependencies, disabled `2.1` features, and old-line release wording.

## Phase Gates

### `tmp/2.0` To `2.3.0`

`2.3.0` is the maintained Factorio `2.0` port of the MIR 3 compatibility compiler architecture. It removes or disables Factorio `2.1`-only surfaces. Do not describe it as identical to `3.0.0`.

Minimum gate:

- start from the exact `3.0.0` source anchor;
- set `info.json` to version `2.3.0`, `factorio_version = "2.0"`, and `base >= 2.0`;
- remove Factorio `2.1` dependency floors;
- validate hidden optional dependency syntax and official DLC names on the real Factorio `2.0` install;
- remove or guard `2.1`-only cargo modifiers and any other `2.1`-only direct effects;
- verify recipe `categories` / `category` behavior against Factorio `2.0`;
- verify Space Age and Quality behavior against the actual `2.0` install;
- run static validation and Factorio `2.0` binary validation from `D:\Programs\Factorio`;
- run base-only and Space Age/Quality `2.0` load checks;
- run selected local mod-library checks;
- compare planner and report output against `3.0.0` expectations;
- update README, changelog, Mod Portal copy, and release notes for Factorio `2.0`;
- build and inspect the package;
- promote to `legacy` only after all gates pass.

After publication:

1. Upload the exact validated zip recorded in `.mir/branches.yml`.
2. Verify the Mod Portal lists MIR `2.3.0` for Factorio `2.0`.
3. Tag the GitHub source point for the released `legacy` commit.
4. Mark `.mir/branches.yml` as `published` in a follow-up release-evidence commit.
5. Treat the released `2.3.0` zip as immutable.

Do not rebuild `2.3.0` after upload unless a release-blocking issue is found. If the payload changes after publication, the next package is `2.3.1`.

### Portable Return To `dev` And `3.0.5`

After `2.3.0` and every later ring, bring back only portable improvements to `dev`: validation runner improvements, package hygiene checks, target manifest fixes, report-diff tooling, deterministic ordering fixes, generic platform-adapter fixes, clearer diagnostics, docs corrections, release-process hardening, test fixtures that also make sense for Factorio `2.1`, and bug fixes in shared compiler logic.

Do not release these immediately as `3.0.1`. Keep them on `dev` while the `3.0.0` backport rings continue. Use `3.0.5` for the accumulated Factorio `2.1` patch after the `2.0` port is published, the `1.1` port is either published or has produced clear lessons, the `1.0` / `0.18` policy is decided, and a short community-feedback window has surfaced current-line issues.

Do not bring back target-line metadata, dependency-floor downgrades, removed `2.1` dependencies, disabled `2.1` features, lower-target compromises as default Factorio `2.1` behavior, or `2.0` release wording.

Rule:

```text
Old branches teach the compiler better boundaries.
They do not drag the modern line backward.
```

### Emergency `3.0.1` Policy

Do not cut `3.0.1` unless the current Factorio `2.1` line has a serious release-blocking issue:

- `3.0.0` has a serious Factorio `2.1` load failure;
- a migration breaks saves;
- a generated technology ID problem appears;
- a package hygiene issue affects users;
- a public Mod Portal upload is materially wrong;
- a critical compatibility fix is safe and already validated.

Everything else accumulates for `3.0.5`.

### `tmp/1.1` To `1.9.3`

`1.9.3` is a Factorio `1.1` compatibility port generated from the MIR 3 architecture. Feature parity with `2.x` and `3.x` is not promised.

Required cuts:

- remove Space Age, Quality, Recycler, and Elevated Rails;
- remove cargo platform and landing-pad modifiers;
- replace `storage` with `global` or remove runtime code;
- disable recipe productivity unless proven in Factorio `1.1`;
- use modern non-Space-Age science packs only;
- avoid Factorio `2.x` dependency syntax leakage;
- validate lab productivity and worker robot battery effect support;
- validate infinite `max_level` and `count_formula`;
- validate old recipe result schema and icon schema;
- validate migrations or omit them.

Required proof:

- `info.json` version is `1.9.3`;
- `factorio_version` is `1.1`;
- the matching Factorio `1.1` binary loads the package;
- science packs are target-valid;
- technology effects are target-valid;
- `max_level` and `count_formula` load in the target binary;
- old recipe schema assumptions are proven;
- package hygiene passes;
- release notes describe this as a compatibility port.

`1.1` is the first hard reduction ring. Do not expect it to behave like the Factorio `2.0` port.

### `tmp/1.0` To `1.8.0` / `1.8.1`

Ring 3 follows the same synthesis pattern as `1.9.3`: start from the `3.0.0` source anchor plus portable `2.3.0` and `1.9.3` lessons, then remove or adapt only the surfaces the target binary cannot support.

The public version split is:

- `1.8.0` for the Factorio `0.18` bridge/archive package;
- `1.8.1` for the true Factorio `1.0` package;
- `1.8.2+` for any later Factorio `1.0` fixes.

As of 2026-07-10, `1.8.0` is the published Factorio `0.18` bridge/archive package. Its immutable archive is `dist/more-infinite-research_1.8.0.zip` with SHA-256 `D785E6EBE7A72E6E9F01A3F89774A6AA30479430410447F603FEF1E0B9BD7B24`, `300620` bytes, `121` entries, and `0` forbidden release entries. Static validation, Factorio `0.18` binary validation, and Factorio `1.0` bridge-load validation are recorded as passed in `.mir/branches.yml`.

The `1.0` follow-up must not be made by changing only the `1.8.0` metadata. Build `1.8.1` from the `1.9.3` reduced source posture plus proven `1.8.0` bridge lessons and current `dev` portable fixes. Re-probe anything cut only because Factorio `0.18` rejected it; keep Factorio `2.x` and DLC surfaces cut.

The resolved bridge sequence was:

1. Create `port/1.1-to-0.18` from the validated `1.9.3` source point.
2. Retarget that branch to version `1.8.0`, `factorio_version = "0.18"`, and `base >= 0.18`.
3. Cut any remaining `1.1` assumptions that the Factorio `0.18` binary rejects.
4. Build `dist/more-infinite-research_1.8.0.zip`.
5. Load the exact same zip in Factorio `0.18` and Factorio `1.0`.
6. Publish `1.8.0` only if both binary loads pass.
7. Freeze `1.8.0` after publication unless a severe package or load defect is found.
8. Build `1.8.1` on `tmp/1.0` as the direct Factorio `1.0` package.

Do not treat `1.8.0` as the maintained `0.18` line. It is a bridge/archive exception because Factorio documents `0.18` packages as loadable by `1.0`. Future `1.0` fixes go to `1.8.2+`, not to a higher `0.18` bridge package.

Minimum `1.8.0` metadata:

```json
{
  "version": "1.8.0",
  "factorio_version": "0.18",
  "dependencies": [
    "base >= 0.18"
  ]
}
```

Minimum `1.8.1` metadata:

```json
{
  "version": "1.8.1",
  "factorio_version": "1.0",
  "dependencies": [
    "base >= 1.0"
  ]
}
```

First-release policy for both packages:

- keep target-proven direct-effect infinite technologies;
- keep target-proven base-extension continuations;
- keep `global` runtime state or remove runtime code;
- cut recipe productivity unless a target binary proves the exact modifier;
- cut Space Age, Quality, Recycler, Elevated Rails, cargo logistics, spoilage, agriculture, and Factorio `2.x` prototype repairs;
- do not add new features in `1.8.1` beyond what is needed for direct Factorio `1.0` compatibility.

Release wording for `1.8.0`:

```text
MIR 1.8.0 is a Factorio 0.18 bridge/archive compatibility port derived from
the MIR 3 architecture and the Factorio 1.1 compatibility port. It is provided
for players on the final Factorio 0.18 experimental line and is expected to
load in Factorio 1.0 under Factorio's documented 0.18-to-1.0 compatibility
exception. It is not the maintained Factorio 1.0 line.
```

Release wording for `1.8.1`:

```text
MIR 1.8.1 is the first maintained Factorio 1.0 compatibility port derived from
the MIR 3 architecture and the Factorio 0.18 bridge proof. Feature parity with
2.x and 3.x is not promised.
```

### `tmp/0.17`, `tmp/0.16`, And `tmp/0.15`

These are reduced native-infinite editions:

- `tmp/0.17` to `1.7.0`: published first old-line native-infinite proof;
- `tmp/0.16` to `1.6.0`: next old-science native-infinite proof, sourced from the 3.0.5 canonical baseline plus synthesized 1.7.0 behavior;
- `tmp/0.15` to `1.5.0`: earliest plausible native-infinite floor.

Required work:

- remove all `2.x` DLC surfaces;
- remove recipe productivity unless binary proof supports it;
- use `global` or no runtime;
- build target-specific science pack maps;
- validate `max_level`, `count_formula`, and every direct effect by binary;
- use minimal settings and target-era icon and recipe schemas;
- package and load in the matching binary.

### `tmp/0.14`, `tmp/0.13`, And `tmp/0.12`

These are archive finite-ladder reconstructions unless binary proof supports more:

- `tmp/0.14` to `1.4.0`;
- `tmp/0.13` to `1.3.0`;
- `tmp/0.12` to `0.12.0`.

The first proof package should contain one technology, one effect, one finite continuation, target-era science packs, no modern settings surface, and no current infinite generator.

### `tmp/0.11` Through `tmp/0.6`

These are museum/discovery builds. Do not call them release candidates until a matching old binary loads a package.

First tasks:

- acquire the matching binary;
- inspect target base files;
- identify mod structure, technology prototype shape, science pack names, and available effect types;
- build one tiny proof package;
- load it in the target binary;
- only then define the actual feature set.

Do not block `3.0.5` on the full museum ladder unless the archive work is moving quickly. Lessons from `0.14` and older can feed a later `3.0.6` patch or the `3.1.0` tooling and compatibility infrastructure campaign.

## Release Wording Classes

Use these public wording classes:

| Line | Wording |
| --- | --- |
| `3.x.x` | Canonical MIR release for Factorio `2.1`. |
| `2.x.x` | Maintained Factorio `2.0` port of the canonical MIR architecture. |
| `1.9.x` | Compatibility port for Factorio `1.1`; feature parity with `2.x`/`3.x` is not promised. |
| `1.8.0` | Frozen Factorio `0.18` bridge/archive package; expected to load in `1.0` only as bridge proof. |
| `1.8.1+` | Maintained compatibility port for Factorio `1.0`; feature parity with `2.x`/`3.x` is not promised. |
| `1.7.x` / `1.6.x` / `1.5.x` | Reduced native-infinite edition for Factorio `0.17` / `0.16` / `0.15`. |
| `1.4.x` / `1.3.x` / `0.12.x` | Archive finite-ladder reconstruction. |
| `0.11.x` through `0.6.x` | Museum/discovery build. |

## Improvements To Keep The Plan Safe

The plan is sound, but these guardrails would make it safer:

- Tag or record the exact source commit for every backport before editing target-line metadata.
- Keep `tmp/*` as staging only; release from `main`, `legacy`, or explicit target-line release branches.
- Use worktrees for simultaneous `dev`, `tmp/2.0`, and future target-line ports.
- Add a machine-readable target-line matrix so docs, release profiles, and validation scripts agree on version range, Factorio binary, local mod library, metadata floor, and known exclusions.
- Do not merge target-line metadata changes back to `dev`; cherry-pick portable code fixes instead.
- Make the `1.9.0` through `1.9.2` historical exception visible in release notes because the new scheme reassigns `1.9.3+` to Factorio `1.1`.
- Keep the Factorio `0.18` bridge frozen at `1.8.0` unless a severe package/load defect is found. Do not invent a new version line for `0.18` unless the locked scheme is explicitly reopened.
- Do not start broad 3.0 backports until the 3.0 architecture, migration manifest, claim manifest, and negative fixtures are stable on Factorio `2.1`.
