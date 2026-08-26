---
title: "ADR 0029: Dual-Plane Repository"
status: current
applies_to: "3.2.5, 2.5.5, 3.3, 2.6"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-12
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-dual-plane-repository
  - mir-logical-repository-paths
---

# ADR 0029: Dual-plane repository

## Context

MIR currently mixes normative product specifications, operational release state, generated views, verification schemas, tests, tools, historical source copies, and disposable outputs across `.mir/` and several root directories. The overlap makes ownership ambiguous and hard-codes physical paths into durable records.

The existing `.mir/target-lines/` tree also duplicates 17 complete historical source trees. Exact integrity is valuable, but keeping materialized copies in the active checkout is not the smallest reproducible authority.

## Decision

MIR adopts two repository planes:

- the visible product plane contains package source, `spec/`, `validation/`, `tools/`, `fixtures/`, and `docs/`;
- the hidden `.mir/` plane contains control policy, lifecycle state, release records, bounded evidence authority, and generated views.

`.mir/control/paths.yml` is the logical path authority. `.mir/control/aliases.yml` preserves read-only historical resolution. Durable and machine-local path resolution are separate services.

The public maintainer interface is `tools/mir.ps1`. Old command paths forward to the same implementation during a measured compatibility window.

Release deltas move from `.mir/releases/deltas/` to `.mir/releases/deltas/`. Approval becomes record state. Historical text is not rewritten.

Historical source copies are replaced by per-version source locks only after two independent exact materializations reproduce paths, Git modes, blobs, file counts, logical bytes, and supported package identities.

The MIR 3 terminal checkout now implements that replacement. `.mir/releases/sources/published-source-locks.json` binds each exact tag, commit, root tree, file count, logical byte count, and distribution identity. The release-history gate independently resolves the former staged snapshot subtree retained at its immutable parent commit and the corresponding release tag/commit tree. Exact tree equality proves path, Git-mode, and blob equality without retaining 17 duplicate working-tree copies. The retirement commit remains in ordinary history, and offline Git-bundle custody remains explicitly pending until the terminal EOL archive and restore rehearsal.

## Alternatives

Keeping the existing structure avoids migration work but preserves duplicate authorities and checkout weight. Moving everything into `.mir/` hides product contracts. Moving operational evidence into visible product directories confuses desired state with observed state. Encoding approval in a directory name forces state transitions to become path changes.

## Consequences

The root becomes smaller and each durable path gains one owner and writer. Specifications and verification become easier to discover. CI and maintainers gain one stable command surface. Historical aliases and wrappers add temporary complexity, and the migration requires systematic path-parity testing.

Removing active target snapshots reduces future checkout and index weight but does not rewrite prior Git history.

## Migration

The migration proceeds through inventory, path contracts, CLI facade, workspace consolidation, schema/test relocation, tooling relocation, specification relocation, `.mir` reshaping, source-lock reconstruction, and alias sunset. Package bytes remain frozen throughout the relocation train.

New writes become canonical before old paths are removed. A move is complete only when the path catalog, ownership manifest, module registry, test catalog, documentation, CI, and generated views agree.

## Reversal

Each phase is an independent commit. Before wrapper sunset, reverting a phase restores the former physical path without changing durable IDs or package bytes. Historical aliases remain valid even after execution wrappers are removed.
