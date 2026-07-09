---
title: "Documentation Governance"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Documentation Governance

Documentation is versioned repository evidence. It is not shipped in the
Factorio release zip.

Rules:

- Every Markdown file under `docs/` has frontmatter.
- Every Markdown file under `docs/` is registered in `.mir/docs.yml`.
- Each topic has one canonical active page.
- Archived pages are historical only and must name a replacement.
- Active docs do not link to archive material unless the link is explicitly
  historical context.
- Compatibility pages must match `.mir/compatibility.yml` and fixture evidence.

Run docs governance through static validation:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

