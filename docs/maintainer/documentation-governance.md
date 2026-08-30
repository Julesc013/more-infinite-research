---
title: "Documentation Governance"
status: current
applies_to: "MIR 4.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - documentation-governance
---

# Documentation governance

Documentation is versioned repository evidence. It is not shipped in the Factorio release zip.

Rules:

- Every Markdown file under `docs/` has front matter.
- Markdown front matter is the editable authority for title, status, applicability, audience, type, owner, review date, succession, and source-of-truth identifiers.
- Versioned release notes are byte-immutable custody inputs. Their imported source identifiers live in `.mir/docs-immutable-source-truth.json`; the index writer rejects duplicate identifiers in those page bytes.
- `.mir/docs.yml` is a generated compatibility projection. Never edit it by hand.
- Each topic has one canonical active page.
- `historical-checkpoint` marks a superseded development or qualification snapshot; it must name `superseded_by`, `checkpoint_source_commit`, and `checkpoint_candidate_sha256`, using `not-recorded` rather than inventing an identity.
- Archived pages are historical only and must name a replacement.
- Active docs do not link to archive material unless the link is explicitly historical context.
- Compatibility pages must match `.mir/compatibility.yml` and fixture evidence.
- Markdown paragraphs and list items use one logical source line and rely on renderer-managed word wrapping. Do not manually wrap prose to a fixed column.
- Newlines in Markdown represent structure only: headings, paragraph boundaries, list boundaries, tables, block quotes, explicit hard breaks, or code blocks.
- `changelog.txt` is the only documentation file governed by the Factorio 132-character line-width requirement.

Format Markdown prose:

```powershell
.\tools\commands\docs\Format-MIRMarkdown.ps1
```

Regenerate the documentation index, owner dashboard, review-age report, navigation, reference matrix, and compatibility projection:

```powershell
.\tools\commands\docs\Update-MIRDocumentationIndex.ps1
```

Check the generated fixed point without changing files:

```powershell
.\tools\commands\docs\Update-MIRDocumentationIndex.ps1 -Check
```

`-ImportLegacyIndex` is a one-time migration mode. It never edits versioned release notes. Do not use it after front-matter authority is established.

Check Markdown prose without changing files:

```powershell
.\tools\commands\docs\Format-MIRMarkdown.ps1 -Check
```

Run docs governance through static validation:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

