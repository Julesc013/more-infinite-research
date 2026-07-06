# Target-Line Versioning And Backports

Updated: 2026-07-07

This note records the maintainer plan for separating MIR release numbers by
Factorio target line after the `2.2.0` compatibility-platform release. It is a
release-operations note, not a feature-parity promise. Every target line still
needs its own source branch, metadata, package build, Factorio binary, mod
library, validation artifacts, and public release notes before it can be
published.

## Current Transition State

The `2.2.0` release was cut under the old numbering scheme, where the active
`2.x.x` MIR line targeted Factorio `2.1`. After the `2.2.0` release and its
Factorio `2.0` backport are complete, MIR should move to the new target-line
numbering scheme:

| MIR version range | Factorio target line | First planned release in range | Notes |
| --- | --- | --- | --- |
| `1.3.x` | Factorio `0.13` | TBD | Older-line port, validation-gated. |
| `1.4.x` | Factorio `0.14` | TBD | Older-line port, validation-gated. |
| `1.5.x` | Factorio `0.15` | TBD | Older-line port, validation-gated. |
| `1.6.x` | Factorio `0.16` | TBD | Older-line port, validation-gated. |
| `1.7.x` | Factorio `0.17` | TBD | Older-line port, validation-gated. |
| `1.8.x` | Factorio `1.0` | `1.8.0` | New post-transition Factorio `1.0` line. |
| `1.9.x` | Factorio `1.1` | `1.9.3` | `1.9.0` through `1.9.2` remain historical Factorio `2.0` transition releases. |
| `2.x.x` | Factorio `2.0` | `2.5.0` | New post-transition Factorio `2.0` line. |
| `3.x.x` | Factorio `2.1` | `3.0.0` | New current line and compatibility-compiler architecture release. |

The awkward part is intentional and must be documented in release notes:
`1.9.0`, `1.9.1`, and `1.9.2` are historical Factorio `2.0` transition
backports. Starting at `1.9.3`, the `1.9.x` range is reserved for Factorio
`1.1`.

## Branch Roles

Use these branch roles during the transition:

| Branch or worktree | Role | Public release source? |
| --- | --- | ---: |
| `main` | Published release tip for the active current line. | Yes |
| `dev` | Active development line; after the transition this is the Factorio `2.1` / MIR `3.x.x` line. | Not directly unless fast-forwarded to `main` after gates |
| `tmp/2.0` | Temporary Factorio `2.0` staging branch or worktree used to validate backports against a real Factorio `2.0` install. | No |
| `legacy` | Public historical Factorio `2.0` backport branch for `1.9.0` through `1.9.2`. | Yes |
| `tmp/<factorio-line>` | Temporary target-line staging branches for older backports. | No |

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
- performance budgets for large modpacks;
- public ADRs for architecture, settings, migration, claims, and runtime
  boundaries.

`3.0.0` can use existing proof surfaces such as Air Scrubbing, ATAN Ash, ATAN
Nuclear Science, AAI Loaders, Big Mining Drill, and the requested local load
checks, but it should not become a broad K2/Bob/Angel/SE/Py generation release.
The detailed 3.0 architecture charter lives in
`docs/notes/3.0.0-compatibility-compiler-charter.md`.

## Backporting `3.0.0`

Once `3.0.0` is stable on the Factorio `2.1` line:

1. Create target-line `tmp/*` branches or worktrees from the tested `3.0.0`
   source point.
2. Apply target-line metadata and API guards.
3. Run the matching binary and local mod-library validation for each line.
4. Bring portable fixes back to `dev`.
5. Publish only target lines that pass their own validation.

Backports from `3.0.0` should preserve the compiler architecture where the
target Factorio line can support it. If an older line cannot support a surface,
the port should remove or disable that surface and document the exclusion
rather than simulating feature parity.

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
- Decide whether Factorio `0.18` needs its own line or is intentionally
  unsupported in the new mapping.
- Decide whether Factorio `0.12` and older lines are retired, since the new
  scheme starts at Factorio `0.13`.
- Do not start broad 3.0 backports until the 3.0 architecture, migration
  manifest, claim manifest, and negative fixtures are stable on Factorio `2.1`.
