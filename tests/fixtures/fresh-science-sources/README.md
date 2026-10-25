---
title: "Fresh science source data-stage fixture"
status: draft
applies_to: "F210 2.1.23 fresh science source qualification"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-25
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-fresh-science-data-fixture
---

# Fresh science sources data-stage fixture

This private F210 2.1.23 fixture preserves the published 4.7.3 `planetary-data` reproducer shape: an automation-science-pack clone accepted by every current lab, a disabled circular producer, and one disabled producer unlocked by a no-prerequisite `craft-item` owner. Its historical `mir473` identifiers remain fixture-local evidence, not player identities.

`settings-updates.lua` selects the existing `all` science policy. `data-final-fixes.lua` requires retained `recipe-prod-research_*` rows to keep positive typed item quantities, reach the seeded foreign gate without the circular alternative, and retain positive productivity among those rows while leaving the foreign circular technology unchanged. Authored and official prerequisites remain allowed; scripted rows may legitimately use `nothing` effects.

The source witness is `8643cc91bc915e008556a5315dbb0a743247e7ab:fixtures/assert-startup-planetary-data-473`. This synthetic case supplies no real upstream provider identity and must not become a fixture-specific player compatibility row.

This is a data-stage obligation only. It makes no gameplay, laboratory completion, save/reload, migration, multiplayer, performance, or release-qualification claim; the affected native upgrade follow-up remains separate.
