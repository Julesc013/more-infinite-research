---
title: "Documentation Governance"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Documentation Governance

Documentation is versioned repository evidence. It is not shipped in the Factorio release zip.

Rules:

- Every Markdown file under `docs/` has frontmatter.
- Every Markdown file under `docs/` is registered in `.mir/docs.yml`.
- Each topic has one canonical active page.
- Archived pages are historical only and must name a replacement.
- Active docs do not link to archive material unless the link is explicitly historical context.
- Compatibility pages must match `.mir/compatibility.yml` and fixture evidence.
- Markdown paragraphs and list items use one logical source line and rely on renderer-managed word wrapping. Do not manually wrap prose to a fixed column.
- Newlines in Markdown represent structure only: headings, paragraph boundaries, list boundaries, tables, block quotes, explicit hard breaks, or code blocks.
- `changelog.txt` is the only documentation file governed by the Factorio 132-character line-width requirement.

Format Markdown prose:

```powershell
.\scripts\Format-MIRMarkdown.ps1
```

Check Markdown prose without changing files:

```powershell
.\scripts\Format-MIRMarkdown.ps1 -Check
```

Run docs governance through static validation:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

