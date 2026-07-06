---
title: "Target-Line Versioning And Backports"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# Target-Line Versioning And Backports

Updated: 2026-07-07

This note records the locked maintainer policy for separating MIR release
numbers by Factorio target line after the `2.2.0` compatibility-platform
release. It is a release-operations note, not a feature-parity promise. Every
target line still needs its own source branch, metadata, package build,
Factorio binary, mod library, validation artifacts, and public release notes
before it can be published.

## Current Transition State

The `2.2.0` release was cut under the old numbering scheme, where the active
`2.x.x` MIR line targeted Factorio `2.1`. After the `2.2.0` release and its
Factorio `2.0` backport are complete, MIR moves to a locked target-line
numbering scheme. Public MIR version numbers now encode the target Factorio
generation. They no longer only encode MIR's internal architecture generation.

| MIR version range | Factorio target line | First planned release in range | Support class | Notes |
| --- | --- | --- | --- | --- |
| `3.x.x` | Factorio `2.1` | `3.0.0` | Canonical modern | Current-line compiler architecture release. |
| `2.x.x` | Factorio `2.0` | `2.3.0` | Maintained `2.0` backport | First post-3.0 port of the compiler architecture. |
| `1.9.x` | Factorio `1.1` | `1.9.3` | Compatibility port | `1.9.0` through `1.9.2` are transition exceptions for Factorio `2.0`. |
| `1.8.x` | Factorio `1.0` | `1.8.0` | Compatibility port | Factorio `0.18` remains a bridge decision, not a separate locked line. |
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

The awkward part is intentional and must be documented in release notes:
`1.9.0`, `1.9.1`, and `1.9.2` are historical Factorio `2.0` transition
backports. Starting at `1.9.3`, the `1.9.x` range is reserved for Factorio
`1.1`.

The transition rule is:

```text
Legacy mapping era:
  1.9.0 through 1.9.2 target Factorio 2.0.

Target-line mapping era:
  1.9.3 and later target Factorio 1.1.
  2.x.x targets Factorio 2.0 starting at 2.3.0.
  3.x.x targets Factorio 2.1 starting at 3.0.0.
```

## Branch Roles

Use these branch roles during the transition:

| Branch or worktree | Role | New release line |
| --- | --- | ---: |
| `main` | Stable canonical Factorio `2.1` line after gates. | `3.x.x` after `3.0.0` |
| `dev` | Development canonical Factorio `2.1` line. | `3.x.x` after `3.0.0` |
| `legacy` | Stable Factorio `2.0` branch. It receives `1.9.0` through `1.9.2` during the transition and `2.x.x` after the 3.0 architecture port. | `2.x.x` starting at `2.3.0` |
| `tmp/2.0` | Working Factorio `2.0` port branch or worktree. | `2.x.x` starting at `2.3.0` |
| `tmp/1.1` | Working Factorio `1.1` port branch or worktree. | `1.9.x` starting at `1.9.3` |
| `tmp/1.0` | Working Factorio `1.0` port branch or worktree. | `1.8.x` |
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

`tmp/*` branches should be treated as disposable validation workspaces. They can
carry target-line metadata, API removals, and diagnostic experiments while the
port is being proven. Durable fixes discovered there should be cherry-picked or
ported back to `dev`, but target-line metadata downgrades should not be merged
back into the current line.

For safer local work, prefer `git worktree` checkouts for `tmp/*` branches so a
Factorio `2.0` port can be validated while `dev` remains available for Factorio
`2.1` fixes.

## Immediate `2.2.0` To `1.9.2` Flow

The immediate transition plan is:

1. Install a real Factorio `2.0` Space Age-capable binary at
   `D:\Programs\Factorio`.
2. Create `tmp/2.0` from the validated `2.2.0` source point.
3. Change the backport metadata for Factorio `2.0`:
   - `info.json` version becomes `1.9.2`;
   - `factorio_version` becomes `2.0`;
   - base dependency floor becomes `base >= 2.0`;
   - official optional dependencies must not carry Factorio `2.1` floors.
4. Remove or guard Factorio `2.1`-only prototype surfaces, especially cargo
   landing-pad and cargo unloading direct modifiers unless Factorio `2.0`
   validation proves they load.
5. Run the Factorio `2.0` validation lane from `tmp/2.0`:

   ```powershell
   .\scripts\Invoke-MIRValidation.ps1 -StaticOnly
   .\scripts\Invoke-MIRValidation.ps1 -FactorioBin 'D:\Programs\Factorio\bin\x64\factorio.exe'
   .\scripts\mir.ps1 release gate --profile release-targeted-2.0 --factorio 'D:\Programs\Factorio\bin\x64\factorio.exe' --mods 'C:\Projects\Factorio\testmods_2.0' --no-git-pull
   ```

6. Bring portable bug fixes and validation-tool fixes from `tmp/2.0` back to
   `dev`.
7. Revalidate `dev` on the Factorio `2.1` Steam install:

   ```powershell
   .\scripts\Invoke-MIRValidation.ps1 -FactorioBin 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
   .\scripts\mir.ps1 release gate --profile release-targeted-2.1 --no-git-pull
   ```

8. Publish the current-line release from `main` after `dev` is fast-forwarded
   and the release gate passes.
9. Merge or fast-forward the validated `tmp/2.0` port into `legacy` for the
   `1.9.2` release.
10. After `1.9.2`, return durable process/docs/tooling improvements to `dev`
    and begin the `3.0.0` architecture line.

As of 2026-07-07, the `2.2.0` current-line release gate and `main` push have
already been completed once. If a new `2.2.0` build is reopened, repeat the
full current-line gate before publishing another archive.

## `3.0.0` Charter

`3.0.0` should not be framed as "more productivity technologies." It should be
the Factorio `2.1` compatibility-compiler release:

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
- schema-versioned facts, candidates, decisions, stream specs, manifests, and
  compatibility claims;
- one-way module boundaries where `emit/` is the only layer that mutates
  prototypes;
- policy overlays instead of mod-specific behavior scripts;
- stable generated technology IDs and migration rules;
- negative fixtures for loop-risk, hidden, cap-zero, external-owner, science,
  loader-like, and drill-like decoys;
- differential planner report tooling;
- performance budgets for large compatibility targets;
- public ADRs for architecture, settings, migration, claims, and runtime
  boundaries.

`3.0.0` can use existing proof surfaces such as Air Scrubbing, ATAN Ash, ATAN
Nuclear Science, AAI Loaders, Big Mining Drill, and the requested local load
checks, but it should not become a broad K2/Bob/Angel/SE/Py generation release.
The detailed 3.0 architecture charter lives in
`docs/architecture/compatibility-compiler-charter.md`.

## Backporting `3.0.0`

Once `3.0.0` is stable on the Factorio `2.1` line:

1. Create target-line `tmp/*` branches or worktrees from the tested `3.0.0`
   source point.
2. Apply target-line metadata and API guards.
3. Run the matching binary and local mod-library validation for each line.
4. Bring portable fixes back to `dev`.
5. Publish only target lines that pass their own validation.

Backports from `3.0.0` should preserve the compiler architecture only where the
target Factorio line can support it. Do not describe this as backporting
`3.0.0` wholesale to every `tmp/*` branch. The correct policy is:

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

If an older line cannot support a surface, the port should remove, disable, or
report that surface and document the exclusion rather than simulating feature
parity with unsafe runtime behavior.

## Release Wording Classes

Use these public wording classes:

| Line | Wording |
| --- | --- |
| `3.x.x` | Canonical MIR release for Factorio `2.1`. |
| `2.x.x` | Maintained Factorio `2.0` port of the canonical MIR architecture. |
| `1.9.x` / `1.8.x` | Compatibility port for Factorio `1.1` / `1.0`; feature parity with `2.x`/`3.x` is not promised. |
| `1.7.x` / `1.6.x` / `1.5.x` | Reduced native-infinite edition for Factorio `0.17` / `0.16` / `0.15`. |
| `1.4.x` / `1.3.x` / `0.12.x` | Archive finite-ladder reconstruction. |
| `0.11.x` through `0.6.x` | Museum/discovery build. |

## Improvements To Keep The Plan Safe

The plan is sound, but these guardrails would make it safer:

- Tag or record the exact source commit for every backport before editing
  target-line metadata.
- Keep `tmp/*` as staging only; release from `main`, `legacy`, or explicit
  target-line release branches.
- Use worktrees for simultaneous `dev`, `tmp/2.0`, and future target-line ports.
- Add a machine-readable target-line matrix so docs, release profiles, and
  validation scripts agree on version range, Factorio binary, local mod library,
  metadata floor, and known exclusions.
- Do not merge target-line metadata changes back to `dev`; cherry-pick portable
  code fixes instead.
- Make the `1.9.0` through `1.9.2` historical exception visible in release
  notes because the new scheme reassigns `1.9.3+` to Factorio `1.1`.
- Record the Factorio `0.18` bridge policy before the `1.8.x` Factorio `1.0`
  line ships. Do not invent a new version line for `0.18` unless the locked
  scheme is explicitly reopened.
- Do not start broad 3.0 backports until the 3.0 architecture, migration
  manifest, claim manifest, and negative fixtures are stable on Factorio `2.1`.
