---
title: "MIR Repository Layout v2"
status: current
applies_to: "3.2.5+"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-03
supersedes: []
superseded_by: []
---

# MIR Repository Layout v2

This is the normative directory and ownership contract for the MIR dual-plane
repository. It complements the shipped compiler boundaries in
`docs/architecture/module-boundaries.md`.

## Principles

1. The visible product plane contains shipped source, specifications,
   validation, fixtures, tools, and documentation.
2. The hidden `.mir/` plane contains operational state, release records,
   evidence metadata, and reproducible views.
3. A durable path has one owner and one permitted writer.
4. Durable records use logical path IDs or repository-relative `/` paths.
5. New writes use canonical paths. Historical aliases are read-only.
6. Factorio package construction is whitelist-based and cannot include
   development directories.
7. `.work/` is disposable. `dist/` contains only publishable packages.
8. Historical evidence text is not rewritten to follow directory moves.

## Root

```text
/
├─ Factorio entrypoints
├─ locale/
├─ migrations/
├─ prototypes/
├─ spec/
├─ validation/
├─ tools/
├─ fixtures/
├─ docs/
├─ .mir/
├─ dist/
└─ .work/
```

The standard repository integration roots `.github/`, `.agents/`, and
`.codex/` remain hidden at root. `AGENTS.md`, `CONTRIBUTING.md`, `README.md`,
`LICENSE`, `.gitignore`, and `.gitattributes` remain at root by convention.

`migrations/` is reserved exclusively for Factorio save and prototype
migrations. Release comparison records belong under
`.mir/releases/deltas/`.

## Visible product plane

### Package source

Factorio entrypoints and the `locale/`, `migrations/`, and `prototypes/`
trees are package-visible. Package membership is determined by the packager
whitelist rather than by repository location alone.

### Specifications

`spec/` contains normative desired-state contracts:

```text
spec/
├─ architecture/
├─ compiler/
├─ compatibility/
├─ package/
├─ performance/
├─ runtime/
├─ schemas/
├─ settings/
└─ targets/
```

Specifications do not contain one-run observations or mutable release state.

### Validation

`validation/` owns propositions, test implementations, evaluation logic,
profiles, adapters, and reviewed baselines. Stable test IDs do not depend on
physical paths.

### Tools

`tools/mir.ps1` is the only public maintainer command surface. Commands and
libraries may move behind it without changing user or CI invocations.

### Fixtures and docs

`fixtures/` owns controlled inputs and one visible catalog. `docs/` owns
human explanation. A generated document names its generator and fails a
drift check when stale.

## Hidden operational plane

```text
.mir/
├─ control/
├─ catalogs/
├─ lifecycle/
├─ releases/
├─ evidence/
├─ views/
└─ local/
```

`control/` owns path, ownership, ABI, repository, revocation, and control
policies. `lifecycle/` owns changes, incidents, and tasks. `releases/` owns
typed release state. `evidence/` owns bounded durable manifests,
attestations, seals, receipts, revocations, and retention roots.

Large immutable evidence objects live in governed external custody with
content digests and at least one independent mirror. Local evidence caches
live under `.work/evidence/` or `.mir/local/`.

`views/` is reproducible and generator-owned. `local/` is ignored and may
contain machine-specific configuration only.

## Release hierarchy

```text
.mir/releases/
├─ records/
├─ closures/
├─ transitions/
├─ deltas/
├─ backports/
├─ lines/
├─ sources/
├─ current.json
├─ distributions.json
├─ convergence.yml
└─ wave.yml
```

`lines/` contains Factorio release-line policy. `sources/` contains exact
per-version reconstruction locks. A version-specific source lock is not a
release line.

Approval is a state inside a delta record. A delta does not change directory
when it moves through draft, review, approval, supersession, or revocation.

## Path services

`RepoPathCatalog` reads `.mir/control/paths.yml` and resolves only canonical
logical IDs and historical repository aliases. It rejects absolute paths,
parent traversal, backslashes, case collisions, and link-based durable
authority.

`MachinePathResolver` remains separate. It may resolve Factorio binaries,
local mod libraries, caches, and user-supplied absolute paths, but those
values may be stored only in `.mir/local/`, `.work/`, or environment
variables.

## Naming

- Root directories are short lowercase domain nouns.
- Collections are plural.
- State is record data, not a directory name.
- Repository paths use ASCII and `/`.
- Generic names such as `misc`, `new`, and `common` are forbidden.
- `views` names reproducible projections; `baselines` names reviewed
  expectations.
- Public command names are stable even when implementation files move.

## Workspace and distributions

`.work/` contains build, cache, context, evidence-cache, line-materialization,
log, output, playtest, staging, temporary, and worktree data. Everything
under it can be removed and reconstructed.

`dist/` contains only exact publishable candidates or released packages.
Raw reports, playtest trees, staging archives, and logs are forbidden there.

## Migration invariants

During the 3.2.5 layout migration:

- C31 archive bytes and normalized package content remain unchanged;
- no package-visible product change is mixed into a relocation commit;
- an old command forwards to exactly one implementation;
- new writes target canonical paths only;
- historical evidence retains its original bytes;
- each move has parity, rollback, and legacy-reference tests;
- target snapshots are removed only after two exact reconstructions.

The minimum layout gate checks ownership, canonical paths, alias resolution,
case collisions, traversal, absolute durable paths, Git links, package
membership, generated provenance, and legacy write attempts.
