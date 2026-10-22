---
title: "Diagram sources and rendered atlas"
status: draft
applies_to: "MIR replacement development"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-diagram-assets
---

# Diagram sources and rendered atlas

[Open the self-contained visual atlas](index.html). No browser network access, JavaScript service, Mermaid CDN or font download is required to view it.

`catalog.json` is the single developer-only source for the graph records. Each record produces an editable `.mmd` flowchart and semantically matching `.svg` and `.png`. The rendered layouts use Graphviz; **a Mermaid renderer was not executed** in the preparation environment. The Mermaid export uses the documented basic flowchart/subgraph/edge/class syntax. Validate it in the chosen Mermaid consumer before treating that renderer integration as tested.

The graph records are not runtime data, an intermediate representation of MIR research, or a second product specification. Focused Markdown specifications remain normative. Generated files are not edited independently; amend a record and regenerate. The embedded Mermaid text in the atlas is identical to its `.mmd` file.

## Diagrams

| ID | Question |
|---|---|
| 01 | How does the whole mod fit together? |
| 02 | What runs during Factorio's ordered startup rounds? |
| 03 | How does Generator preflight avoid unsafe omission? |
| 04 | How do declarations become effective settings? |
| 05 | Who owns data and what crosses the startup/runtime boundary? |
| 06 | How does an independent extension call the API? |
| 07 | How do save load and multiplayer join differ? |
| 08 | What must a save upgrade prove? |
| 09 | What are the four determinism contracts? |
| 10 | Which checks run, and when? |
| 11 | Which repository responsibilities enter the player package? |
| 12 | What work and footprint do we measure? |

The separate cutover diagram is transition-only and retires with adoption tooling. Permanent diagrams use unversioned responsibilities or package-relative paths, so moving this directory does not create stale source-prefix references.

## Rebuild

Run the supplied `render_diagrams.py` with Python 3.10+ and Graphviz `dot`. Use the actual tools/docs roots selected by the checkout; the renderer itself does not assume a staging prefix.

```text
python <tools-root>/render_diagrams.py --catalog <docs-root>/diagrams/catalog.json --output <docs-root>/diagrams
python <tools-root>/render_diagrams.py --catalog <docs-root>/diagrams/catalog.json --check
```

Rendering replaces only the generated files named by the catalogue and its `index.html`; it does not delete source or install packages. The prepared PNG/SVG files mean Graphviz is not required for normal reading or MIR gameplay.
