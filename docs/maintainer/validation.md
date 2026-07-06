---
title: "Validation"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: ["testing.md"]
superseded_by: []
---

# Validation

Run static validation:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Run narrow governance checks first when the change is scoped:

```powershell
.\scripts\mir.ps1 docs check
.\scripts\mir.ps1 manifests check
.\scripts\mir.ps1 architecture check
```

Run runtime validation when a Factorio binary is available:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\path\to\factorio.exe"
```
