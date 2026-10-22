---
title: "Repository and contribution contract"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-repository-specification
---

# Repository and contribution contract

`REPO-01` — One active player source root (`source/`), one normative specification root (`spec/`, singular), one documentation root, and one public MIR API. Historical releases live in existing preserved Git refs/artifact custody, not active duplicate architecture trees. Development integrates through `dev`; `main` is the maintained release until accepted promotion. Do not add a permanent product-major branch solely for the rewrite.

## Names and documentation

Lowercase descriptive directories; snake_case Lua/Python modules and functions; existing prototype/setting/public-interface identities preserved byte-for-byte where compatibility requires. Use stable concept names such as `research/generator.lua`, `api/v1/data.lua`, `api/v1/runtime.lua`. No product number in new internal namespaces, root directories or stable requirement IDs. Public API-major routing is `api/v1` for the new native contract, distinct from the older preview wire semantics; it is not changed for every product release.

The specification owns requirements; source owns the implementation/declarations; tests own independent expected examples; docs explain use. Do not maintain several writable copies of the same catalogue or acceptance state. Generated inventories are clearly marked, reproduced by one small extraction path and never game inputs. The existing request ledger is migrated once retaining its original IDs, text and decisions.

Keep `AGENTS.md` short. It routes a contributor to this index and a task-specific contract; it does not restate all specs or order every agent to read history. Current-task packets include only the input refs, relevant pages, affected source, expected result and commands. Token estimates are approximate; file/word counts and required-reading scope are directly auditable.

Use front matter for docs during coexistence with the existing documentation conventions. One logical line per prose paragraph. Avoid maintaining a second generated docs-governance estate solely for the replacement. Retire obsolete required readers through an explicit reviewed cutover, not by disabling branch protection after a failure.

## Change contract

`REPO-02` — A nontrivial task states: observable outcome; applicable requirement IDs; exact inputs; permitted files; simplest approach; reads/copies/retained state and work bound; independent expected result; executable tests; stop condition. A short PR description is sufficient for ordinary work.

No unrelated refactor, new framework, dependency or public method because it seems future-proof. A new abstraction needs an actual second use or a concrete safety boundary. One author does not silently weaken the oracle or release threshold to make their patch pass. Architecture/API/continuity changes get independent review.

After a bounded batch return source/package identities, observed behavior/tests, performance only where measured, remaining gaps and the next smallest action. Do not continue the whole rewrite merely because another improvement is possible. No broad promise of unattended work or evidence from model agreement.

## Portable build/test operations

Reuse qualified existing native tools if they fit. Read their actual parameters. Do not invent a `mir test` command until it is implemented. A future small project entrypoint may compose real commands, but a universal orchestration system is not a prerequisite for the first slice.

Packaging, performance and test receipts belong outside player source. Raw native logs/saves/mod archives remain local or in approved durable artifact storage, with compact portable references in Git. Never redistribute third-party/proprietary game or mod bytes just because a fixture uses them. Keep licenses and provenance.

## Current tree and history

`REPO-03` — Every tracked path removed at cutover has a reviewed disposition: superseded implementation; transferred current requirement; retained regression/migration; preserved history; or unresolved. Unresolved prevents deletion. Also preserve untracked local saves, dirty files and unique local commits; Git history alone does not capture them.

The active tree must not contain obsolete product-major source/spec/doc/SDK subtrees after qualified cutover. Do not replace them with a large `archive/` or `.mir/history/` directory. Keep only small current source pointers and regression material that has a current consumer. `.mir/` is not preserved as a sacred folder: transfer useful facts, retire old generated authority and remove it if no active consumer remains. AIDE is optional external developer assistance, not a second policy or runtime dependency.

This does not require removing old version numbers from changelogs, historical source URLs, test fixture identities or migration filenames. Such strings may protect compatibility. Cleanup must be based on responsibility and active dependencies, not blind find/replace.

`REPO-04` — Filesystem relocation is a separate semantic-neutral commit. The package root remains relative; production import/asset paths contain no checkout prefix. Check dependency closure, case-sensitive path resolution, staged/canonical docs links, exact member parity, final-layout native smoke and generated metadata. Do not combine formula/ID/migration changes with the move.

## Authority and permissions

Standing authorization for ordinary reviewed dev branches/PRs does not imply authorization for `main`, publication, credential/control changes, data deletion or installed-engine mutation. Preserve dirty work and recover active test library controls. Observe current maintainer pauses, resource guards and execution ownership. No reset/clean/force-push/tag move as a shortcut to synchronization.

Root replacements are adopted by review, not auto-installed by a documentation ZIP. Preserve existing release, filesystem, engine and signing safeguards until their replacements are explicitly accepted. Retiring obsolete internal tests is legitimate; erasing required behavior is not.

## Temporary roots and API-major roots

`REPO-05` — Final responsibilities use the unversioned roots `source`, `spec`, `docs`, `tests`, `tools`, `targets` and `sdk`. A temporary staging component is removed only by the reviewed file-disposition map. `api/v1` is a real public compatibility boundary, not product-major staging, and survives.

Permanent diagrams describe package-relative paths or unversioned repository responsibilities. The transition diagram and import/cutover instructions live under the retirement list and are removed at final cutover. A rendered HTML atlas contains its graphics inline and has no dependency on a network renderer; diagrams never become a second normative specification.

The revised drop-in keeps root document changes staged. Extracting it can replace an older pack's same-named staged files; compare their hashes first with the read-only merge checker. Unknown local edits are conflicts, not permission to overwrite.
