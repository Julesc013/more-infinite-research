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

The science-pack productivity family must also contain exactly one `0.10` effect for each fixture producer. Run40166552270's earlier predicate passed while candidate effects totalled146 versus published148; the original family dynamically targets real lab inputs, so both missing producer effects require explicit checks. The stronger predicate changes fixture input bytes and needs a new native execution; the earlier startup pass is retained under its actual weaker scope.

The source witness is `8643cc91bc915e008556a5315dbb0a743247e7ab:fixtures/assert-startup-planetary-data-473`. This synthetic case supplies no real upstream provider identity and must not become a fixture-specific player compatibility row.

The [candidate selection](../../profiles/fresh-science-sources-mir5-f210-2123.json) and [published comparator](../../profiles/fresh-science-sources-published-f210-2123.json) retain the same exact 2.1.23 engine, official-mod closure, observer and fixture, changing only the MIR version/archive. The candidate is the verified9fc package; the comparator checksum comes from the public [v4.7.3 checksum asset](https://github.com/Julesc013/more-infinite-research/releases/download/v4.7.3/SHA256SUMS.txt). The native worker must verify actual archive bytes and stage this fixture from its selected immutable source before using existing `Invoke-NativeFixture.ps1 -CreateOnly` with the matching expected MIR archive hash. These profiles include MIR explicitly, as that runner requires; `Invoke-PrototypeCapture.ps1` instead requires a profile without MIR and cannot consume them directly. These are small direct-library selections, not populated mod directories or an executed result.

This is a data-stage obligation only. It makes no gameplay, laboratory completion, save/reload, migration, multiplayer, performance, or release-qualification claim; the affected native upgrade follow-up remains separate.
