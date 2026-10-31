---
title: "Named science replacement data-stage fixture"
status: draft
applies_to: "F210 2.1.23 named electromagnetic-science replacement"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-named-science-replacement-fixture
---

# Named science replacement data-stage fixture

This private F210 fixture removes the canonical `electromagnetic-science-pack` recipe and its one matching unlock during `data-updates`. The existing gear research has no authored electromagnetic ingredient, so the shipped `all-official` policy must add the replacement rather than rewriting an authored vector. The fixture then supplies two disabled item producers: an `a-*` source locked behind a research unit consuming that same science pack, and a `z-*` source unlocked by a no-prerequisite `craft-item` trigger.

The final predicate requires enabled MIR gear research to retain the complete official typed science vector, its authored hard gates, and the seeded owner in place of the removed electromagnetic named gate. It rejects the circular owner, changed quantities, missing canonical-recipe replacement, and changes to the fixture-local foreign technology. The direct seeded-versus-circular rule is independently recovered from published 4.7.3 `fixtures/assert-startup-planetary-data-473` at `8643cc91bc915e008556a5315dbb0a743247e7ab`; the historical fixture is synthetic and supplies no upstream-mod claim.

The pinned published selection and the matching frozen MIR5 selection are CreateOnly comparators. The MIR5 profile binds `more-infinite-research_5.0.21000.zip` SHA256 `428A789CA03828D2F7F93EC65C49FD3157FD6D547CC569DDA2C0129D6504647A` from accepted source `5658246a7b8ea213d84496c420042c2ea9ad2eaa`; it keeps the same exact F210 official closure, observer, and fixture inputs as the published arm. This fixture makes no native, gameplay, lab, save, reload, migration, multiplayer, performance, or release claim.
