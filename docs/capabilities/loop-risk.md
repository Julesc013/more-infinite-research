---
title: "Loop Risk Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Loop Risk Capability

Loop-risk detection blocks or reports recipes involving self-return, recovery,
recycling, catalyst cycles, voiding, or transmutation. The default is
diagnostic-only unless a narrow stream explicitly proves safety.
