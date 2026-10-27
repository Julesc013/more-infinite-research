# MIR contributor instructions

Read [spec/README.md](spec/README.md) and the task-specific contract. [docs/development.md](docs/development.md) owns current commands and coordination; [docs/progress.md](docs/progress.md) records exact evidence and remaining release work. MIR5 is incomplete until its acceptance and publication gates pass.

## Source and architecture

- `source/` is the sole canonical editable player source. Compose the normal editions, including selected F018, and separately labelled best-effort historical builds from shared components and narrow capability adapters. Do not create whole-version source copies.
- Use authored native technologies and the small deterministic Generator: finite local preflight, stable manifest rows and one publication. No discovery solver, fixed-point planner or recursive technology/recipe traversal. Necessary bounded recipe collection stays outside the Generator. Compatibility policy never mutates prototypes; admitted emission code alone owns generated technology mutation.
- Preserve technology/settings/API identities, published migration filenames, original request IDs/text/decisions, license notices and complete target histories. Retain the full authored README, including badges, catalogue, settings, examples and troubleshooting.
- Keep docs, fixtures, tests, tools, SDK, guidance, CI, build and dist outside player ZIPs. No preview or developer tool gains mutation, release or support authority merely by existing.
- Source owns implementation, spec owns requirements, tests own independent expectations and docs explain use. Preserve exact historical Git/artifact references; do not keep an obsolete active compiler/framework or a new history estate.

## Workflow and custody

- `dev` is dedicated to MIR5 in the canonical layout. Future MIR4.7 maintenance uses separate task branches from published tags; follow [the development and maintenance policy](docs/development.md#development-and-maintenance-lines).
- Maintainer standing authorization covers branches, pushes, PRs, normal checked merges into `dev`, local synchronization and removal of completed clean disposable work branches. No repeated permission is needed. Enforced branch rules and required checks remain mandatory.
- Commit and push completed reviewable units with detailed validation and limitations; merge frequently through PRs and read back exact remote trees. Preserve Aero's original commits and separate review branches. Never reset, clean, force-push or rebase shared work as a synchronization shortcut.
- Before output batches, run `tools/commands/workspace/Test-MIRDevelopmentHealth.ps1`. Resolve actual disk pressure through bounded batches or existing guarded cleanup. A dirty/unique checkpoint needs a commit/push or explicit preservation disposition; it never disables Git/GitHub.
- Preserve dirty worktrees, unique commits, original saves, active evidence, adverse receipts and delivered packages. Only remove disposable clean worktrees after remote readback. Retain unique custody at a discoverable primary-checkout location.
- The primary checkout is the final handoff: active branch clean and equal to its remote, accepted packages hash-verified in `dist`, matching release notes/upload text present. Main and dev may differ during next-release work.
- Parallel agent work is limited to root plus two bounded workers with explicit file ownership. One worker owns heavy native execution; at most one active and one pending native assignment. Hold builds and host suites during accepted same-machine timing.

## Tests and engines

- Inspect/materialize `tests/Test-MIR5HostControls.ps1 -Plan` before tests; run the narrow selected controls first. Full host checks use that driver and an explicit pinned Lua runtime. Native, save, physical output, multiplayer/client and performance results require their affected exact scenarios. No fixture existence, host count or model agreement substitutes for gameplay evidence.
- Reuse native evidence only for the exact trusted inputs; adopt matching in-progress work. Never relabel an old result as current or erase an earlier failure. Public claims name exact evidence and limits.
- Test profiles contain small selections only. Use one exact archive per engine-family direct library under exclusive ownership, restore previous controls, keep outputs separate. Never copy/hardlink/extract dependency libraries or recreate retired populated profiles. Missing archives are missing inputs.
- Never hardlink with either endpoint outside the executing checkout. External testmods paths are local input locators, not repository dependencies. Preserve portable definitions and unique reproducers.
- The current Steam installation is for Factorio2.1 only; historical engines remain separate. Do not download, replace, retarget or mutate Steam depots for historical engines without explicit maintainer authority. Inspect actual exact engine versions/hashes before native work.
- On Black Glass verify Windows identity and read-only GitHub status in real `BLACKGLASS-WIN1\Jules` context before authentication claims. Expected account is `Julesc013`. Isolated/service-context credential failures are non-authoritative. Never print, replace, switch or log out credentials. Do not request login unless two real-user read-only checks confirm failure.

## Release and documentation

- The maintainer authorizes completing MIR5, then qualified main promotion and canonical `v5.0.0` tagging, unsigned if the enrolled key is unavailable. Agent-managed publication is GitHub-only for all releases; the maintainer handles Mod Portal publication, credentials and readback. Mod Portal access is not an agent completion gate. Authorization never waives remaining acceptance. After verified5.0.0 delivery, continue authorized5.0.1 fixes/performance/stress work.
- Freeze exact committed source and accepted assets before tagging. Reconcile existing remote objects and lost responses by release ID; stage the entire inventory in one draft, verify names/hashes, publish, then verify anonymous downloads and local delivery. Preserve published objects and historical receipts.
- Keep GitHub releases mutable. Run existing `tools/commands/release/Test-MIRGitHubAdministration.ps1` and its distinct release-immutability probe immediately before publication; require both to pass. Never change repository/organization controls or enable immutability to bypass a gate.
- Titles are exactly `MIR MAJOR.MINOR.PATCH`; notes begin with a summary then concise changes, without repeating the title as a heading. Public assets are individual player ZIPs and useful integrity files; keep bundles, inventories, upload instructions and developer records in source/local custody.
- Set each edition's exact minimum `base >= x.y.z` from accepted qualification, keeping two-part `factorio_version`. Use the same minimum in package metadata and download copy. Numeric codec is `100 * integer(CCC) + SOURCE_PATCH`, padded to five digits; final digits are source patch, never a retry or RC counter. Check ZIP root/info/changelog/manifest/filename/tag/copy together. The historical `v4.2.0-stable` tag exception grants no future suffix exception.
- Markdown docs/specs use front matter and one logical source line per paragraph. Only Factorio changelogs have a132-column bound. Current repository checks replace the retired generated MIR4 documentation/assurance estate; do not hand-edit historical generated receipts or import that estate as a new dependency.
- Root `CHANGELOG.md` is the authored master release history; `python -B tools/changelog.py --write` renders tracked `source/changelog.txt`. Commit both together. The formatter freshness and package controls enforce their agreement; never maintain separate editable edition histories.
