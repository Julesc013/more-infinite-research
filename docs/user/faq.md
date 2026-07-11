---
title: "FAQ"
status: current
applies_to: "3.0.0+"
audience: player
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# FAQ

## Can MIR add infinite research that changes module effects at runtime?

Not cleanly. Factorio 2.1 has no technology modifier or runtime API that edits
the effects of every placed module. Replacing modules with a prototype per
research level would bloat prototypes and saves, while invisible beacons would
change machine and beacon semantics. MIR 3.0.5 therefore supports productivity
research for crafting modded modules, but does not claim dynamic infinite
module-effect research.

## Does MIR raise Factorio's recipe productivity cap?

Only when you explicitly select a non-default Recipe productivity cap. The
default leaves every recipe cap unchanged. If you raise it, use the generated
recycler return control or the self-recycling scope guard to manage loop risk.

## Does MIR require Space Age?

No. Space Age content is optional and gated by concrete active prototypes.

## Does MIR claim full support for every listed mod?

No. Public compatibility claims are scoped to the tested family or load profile.
