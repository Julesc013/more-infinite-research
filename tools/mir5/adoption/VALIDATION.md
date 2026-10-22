# MIR specification and diagrams — validation record

Prepared 22 October 2026. **Scope: documents, diagram assets and adoption tools. Not MIR product qualification.**

## Executed

| Check | Observed result |
|---|---|
| Uploaded predecessor pack | 39 archive members inspected; original pack check and 32 cutover tests passed again |
| Revised Python suite | 60 tests passed; 0 failures; 0 skips |
| Document/record checks | 32 Markdown, 11 JSON, 8 Python files; 65 local links; 69 defined requirement IDs |
| Diagrams | 13 rendered diagrams: 12 permanent, 1 transition-only; Mermaid, SVG and PNG supplied |
| Render reproducibility | 41 generated files, including both atlases, byte-identical on a second render in this same Graphviz/font environment |
| Browser | Chromium 144.0.7559.96, HTML supplied through set_content: 12 permanent SVG sections, no page errors or network requests, no desktop/mobile body overflow |
| Full-pack synthetic cutover | 105 tracked fixture inputs → 78 outputs; 27 retirements; 17 link rewrites; source unchanged |
| Byte preservation | 52 retained non-Markdown files compared, including 3 synthetic player-member fixtures |
| Final layout | No staging directories or current-text staging-prefix references remained; API-major and migration paths survived |

The source and final-layout fixture were synthetic, not a checkout of the complete live MIR repository. The helper's plan requires explicit per-file dispositions and refuses unresolved/dirty/stale/colliding input. It exports a new outside directory and never deletes or modifies the source.

## Not executed or established

All **30 product acceptance cases remain not run**. The **17 continuity subject groups remain unreconciled**; no complete technology, setting, request or migration inventory is claimed. No Generator/API implementation, Factorio native test, migration, multiplayer client or performance measurement was performed. There is no measured speedup or proof of full feature parity.

The Mermaid files are generated from the same graph records as the SVG/PNG. Graphviz rendered the visual files; a Mermaid renderer could not be installed and was not executed. The supported exported syntax is deliberately limited to flowcharts, groups, nodes, edges and styling. Validate the chosen Mermaid consumer separately. The rendered offline atlas does not depend on that renderer.

The browser's direct file URL route was blocked by container policy; the self-contained HTML was tested with Playwright set_content. No browser network requests were needed. Linux executed all tool tests; Windows path and CRLF inputs were test fixtures, not native Windows/macOS execution.

## Reproduce pack checks

```text
python tools/mir5/check_pack.py
python -m unittest discover -s tests/mir5 -p "test_*.py" -v
```

Use the read-only merge checker before merging over previously staged files. Root README/AGENTS/CONTRIBUTING replacements remain staged and were not applied. The exact payload file manifest and archive checksums accompany the delivery.

No live GitHub repository, branch, tag, release, installed game, save or local user worktree was changed.
