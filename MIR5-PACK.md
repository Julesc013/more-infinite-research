# MIR specification and visual architecture pack — revision 2

Prepared 22 October 2026. **Proposed contracts, rendered diagrams and checked adoption tooling. Not an implemented mod or native qualification.** The repository uses `spec/`, singular.

## Start here

Open [the architecture explainer](docs/mir5/architecture.md), then [the offline visual atlas](docs/mir5/diagrams/index.html). The atlas shows twelve permanent diagrams with editable Mermaid. The separate [cutover visual](tools/mir5/adoption/diagrams/index.html) covers the thirteenth, temporary diagram. SVG/PNG and Mermaid files accompany every graph.

The focused [specification index](spec/mir5/README.md) routes implementation tasks. Read [the revision audit](tools/mir5/adoption/REVISION.md) for changes to the uploaded pack and [the first bounded batch](docs/mir5/first-batch.md) for implementation order.

## Extract-merge without losing local work

The ZIP is rooted at this repository: it contains `spec/mir5/`, `docs/mir5/`, `source/mir5/`, `targets/mir5/`, `sdk/mir5/`, `tests/mir5/`, `tools/mir5/` and this entry file. It does **not** replace root `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, source releases, CI or licenses. Root changes remain reviewable patches/templates.

An older pack may already have the same staged filenames. **This archive updates those files. Do not extract over local edits blindly.** Extract to a separate directory first, then run this read-only check from the incoming directory:

```text
python tools/mir5/adoption/check_merge.py --repo /path/to/more-infinite-research
```

The result distinguishes absent paths, identical bytes, unmodified predecessor-pack bytes and conflicts. It performs no writes. Preserve local work, review the diff and merge approved files on a development branch. Existing non-pack content is not deleted.

## Validate the adopted pack

```text
python tools/mir5/check_pack.py
python -m unittest discover -s tests/mir5 -p "test_*.py" -v
```

These commands check contracts/links/graph records and tooling. They do not execute Factorio. The root-routing patch is optional and guarded by the observed preimage blobs; run its checker and `git apply --check` before a separately reviewed application. Keep existing engine/library/release safeguards.

## Implementation boundary

`source/mir5/` and `targets/mir5/` contain boundary notes only. There is no installed player package, Generator or accepted engine adapter in this ZIP. API examples are draft consumers, not qualified implementations. Product acceptance cases are explicitly `not_run`, and historical continuity subjects remain unreconciled.

The new contract uses **MIR API 1.0.0-draft.2**: `__more-infinite-research__.api.v1.data` and `more-infinite-research.api.v1`. These are not MIR 4's existing preview wire semantics. The API major survives future product releases; the temporary product-major staging roots do not.

## Final cutover

Use the [reviewed cutover procedure](docs/mir5/cutover.md). Every tracked file gets an explicit disposition; unknown files block retirement. The utility exports a separate candidate and never deletes, resets, commits, pushes or mutates the original checkout. Stale/dirty inputs, path hazards and unresolved collisions are refused.

Only approved staging components are flattened. Preserve current research/settings identities, required historical migration filenames, licenses and useful regression fixtures. Retire obsolete source/spec/docs/tool authority, not those compatibility obligations. One-use adoption files and the cutover diagram retire too. Rebuild equal player members and verify the final layout before stable promotion.

## Truth boundary

The attached validation record states what actually ran. Diagram renders and Python tool tests are not proof of correct gameplay, multiplayer, migration or speed. Factorio was not executed. No live repository was changed. The diagram renderer used Graphviz; Mermaid text is supplied, but a Mermaid renderer was not run. AIDE remains optional external development assistance.
