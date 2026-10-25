---
title: "Named science replacement data-stage fixture"
status: draft
applies_to: "F210 2.1.23 named electromagnetic-science replacement"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-25
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-named-science-replacement-fixture
---

# Named science replacement data-stage fixture

This private F210 fixture removes the canonical `electromagnetic-science-pack` recipe and its one matching unlock during `data-updates`. The existing gear research has no authored electromagnetic ingredient, so the shipped `all-official` policy must add the replacement rather than rewriting an authored vector. The fixture then supplies two disabled item producers: an `a-*` source locked behind a research unit consuming that same science pack, and a `z-*` source unlocked by a no-prerequisite `craft-item` trigger.

The final predicate requires enabled MIR gear research to retain the complete official typed science vector, its authored hard gates, and the seeded owner in place of the removed electromagnetic named gate. It rejects the circular owner, changed quantities, missing canonical-recipe replacement, and changes to the fixture-local foreign technology. The direct seeded-versus-circular rule is independently recovered from published 4.7.3 `fixtures/assert-startup-planetary-data-473` at `8643cc91bc915e008556a5315dbb0a743247e7ab`; the historical fixture is synthetic and supplies no upstream-mod claim.

The pinned published selection is a CreateOnly comparator. A successor profile must be added only after the post-fix MIR5 archive is frozen and its exact filename/version/SHA256 are known. This fixture makes no gameplay, lab, save, reload, migration, multiplayer, performance, or release claim.
