---
title: "Source reconciliation for this proposal"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: guide
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-decisions-guide
---

# Source reconciliation for this proposal

This is transition-only rationale. Its enduring decisions are in the normative specification; remove this page at final layout cutover rather than keeping an obsolete design debate in every agent context.

## Sources read

The four supplied architecture/API/Generator proposals, the replacement contract and first-batch instruction are the requested basis. The source register records their filenames and SHA-256 values. Targeted live reads covered `dev`, root `AGENTS.md`, README, specification layout, documentation governance, `.mir/README.md` and the MEP document. This is not an exhaustive implementation or native audit.

## Explicit resolutions

| Source position | Resolution |
|---|---|
| Most recent proposals use `source/mir5`; replacement contract uses `mod/` | Select `source/mir5 → source`, matching the live maintainer-directed source authority. This changes naming only, not independent fresh implementation. |
| API and MEP are described together | Use MIR API as one name; old MEP was a distinct data-only preview. Audit consumers and translate/version explicitly rather than silently reinterpreting bytes. |
| Generator conceptual `build` assigns nested arrays from input | Require exclusive transfer or fresh nested output. Purity is not enough to prevent post-build alias mutation. |
| Every missing input can skip | Only expected optional-new absence can skip. Historical earned identities and required supported input remain preservation/correctness obligations. |
| All broad scans forbidden | Exact bindings preferred; explicit existing broad settings/targeting may justify one collector outside Generator. No discovery or per-family whole-world scan. |
| Whole-stage zero CPU/no code while loading | Not feasible: prototypes are built at startup. Minimize necessary data-stage work; native bonuses have zero recurring MIR work. |
| One universal cost formula | Illustrative only; retain actual formula/offset/rounding/setting semantics per family. |
| Library/scripted/historical support can move to later minors | Not an automatic scope cut; stable replacement retains delivered applicable behavior. |
| `.mir/history` retained in active root | Current user direction supersedes that proposed archive: move needed facts/tests, keep pinned historical refs outside active architecture, remove retired namespace when unused. |
| Mandatory `extend_technology` or `get_extension_status` | Do not freeze a generic patch language or invent a registry. Narrow real consumers can justify specific future capabilities. |
| All tests first or exhaustive inventory before any experiment | Recover first slices and same-output reference early; full accounting gates deletion/release, not the start of useful experiments. |
| API 1.0 stable by declaration | Candidate until independent required/optional native consumers pass. |

## New items added by this synthesis

Content-addressed, clean-input layout rehearsal; explicit local Markdown-link remapping; collision/symlink/path-escape rejection; no automatic source deletion; separate semantic and layout cutovers; root preimage checks; no duplicate current request ledger; explicit live-regression exceptions to historical-string cleanup; phase-qualified external imports; no advertised cross-stage extension status without a transport owner.

These are proposed design/tooling improvements, not observations that the mod has become faster. General Factorio documentation retrieved for verification identified itself as 2.1.14, so exact target qualification remains local execution work.
