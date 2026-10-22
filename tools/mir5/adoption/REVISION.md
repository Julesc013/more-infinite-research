# Revision 2: review of the supplied pack

## Basis and scope

This revision amends the uploaded 39-file specification/cutover pack and the accompanying two-response synthesis text. Their SHA-256 identities are in the source inventory. Earlier attachments named by the inherited inventory were not independently supplied here; their references remain explicitly inherited, not reverified.

The original pack's document checks and 32 cutover tests were rerun successfully before edits. This establishes a useful baseline for tooling, not game correctness. The live `dev` SHA and `AGENTS.md` blob still matched the inherited observation. No live repository was written.

## Material corrections

| Finding | Revision |
|---|---|
| Determinism was implicit, and some earlier chat prose treated `pairs`/random as inherently nondeterministic | New determinism contract accurately distinguishes Factorio's guarantees, complete inputs, ordering, replay and timing |
| Latest chat flowchart omitted disabled/missing historical technologies | All new flowcharts route released identities through explicit continuity policy; no data-stage save introspection |
| API paths and minimal function sets differed between supplied syntheses | One versioned native draft, matching examples, finite-family preflight; no universal mutation/status registry |
| Forward family prerequisites were underspecified | Local-name map and bounded local-cycle checking; no late finalizer or global planner |
| Cross-stage tables were easy to confuse with native retention | Explicit discarded-startup-state boundary and minimal runtime sources |
| No rendered diagrams were in the upload | Twelve permanent diagrams and one transition-only diagram, editable Mermaid and rendered SVG/PNG plus offline atlases |
| Full source/target staging roots were absent | Non-installable README boundaries only; no fake player or engine implementation |
| Direct extract-merge could overwrite changed staged files | Read-only merge classifier with original-pack hashes, plus explicit collision warning |
| Layout plan parser accepted some nonportable paths/ambiguous JSON | Additional path/type/JSON checks, final HEAD recheck and regression tests |

The source inventory's original 2.1.14 documentation observation is preserved as historical provenance. The official latest pages observed in this revision identified themselves as 2.1.23. Exact-version URL retrieval was unavailable. Neither is native engine qualification.

## Deliberately unchanged

Preserve the applicable player product, original settings/IDs, runtime/Library behavior and all meaningful existing support obligations. Do not narrow everything to a single vanilla recipe, silently convert settings to no-ops, or treat every unconsumed developer preview as mandatory stable functionality. Original unreconciled continuity groups remain unreconciled.

No Generator, runtime API, migration or benchmark implementation is supplied. SDK consumers remain draft fixtures. Complete historical inventory and native qualification remain implementation work. No speedup, save safety or game compatibility is claimed from these document/tool checks.

## Renderer boundary

Graphviz rendered the diagrams from reviewed graph records. Editable Mermaid is generated from the same nodes/edges/groups; a Mermaid runtime could not be installed in this environment and was not executed. The atlas needs no external renderer, network or JavaScript. This limitation does not affect viewing the supplied SVG/PNG.

## Retirement

This audit, import guidance, baseline hashes and cutover-specific diagrams are one-use adoption records. Retire them through the reviewed map after their obligations have transferred; keep a compact source/hash reference if still consumed. Do not copy them into an active historical architecture warehouse.
