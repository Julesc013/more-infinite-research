---
title: "Build And Package"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Build And Package

Build a release package with:

```powershell
.\scripts\Build-MIRPackage.ps1
```

Package validation builds from the current source tree and checks that
repository-only material is excluded.
