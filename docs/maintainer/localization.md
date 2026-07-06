---
title: "Localization Maintenance"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# Localization Maintenance

`locale/en/more-infinite-research.cfg` is the source locale. When English keys change, update every translated
`more-infinite-research.cfg` file to keep the same sections, keys, and placeholders.

Factorio locale rules that matter for this mod:

- Locale folders must use Factorio-supported language codes, such as `en`, `de`, `es-ES`, `pt-BR`, and `zh-CN`.
- English is the fallback locale and must stay complete.
- Do not add spaces around `=`. Factorio treats whitespace around keys and values as literal text.
- Preserve placeholders such as `__1__` exactly.
- Do not keep empty locale folders as placeholders. A locale folder should contain a complete `more-infinite-research.cfg`.
- Generated technology effects can require `[modifier-description]` keys when Factorio does not provide one for a valid modifier type.

Run this after any locale or English string change:

```powershell
.\scripts\Test-MIRLocales.ps1 -AllowMissingSupportedLanguages
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

The first command verifies key parity with English, placeholder parity, supported Factorio locale codes, and empty
placeholder directory cleanup. The second command runs the repository static validation bundle.
