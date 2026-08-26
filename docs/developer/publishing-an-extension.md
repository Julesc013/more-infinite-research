---
title: "Publishing a MIR 4 Extension"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-extension-publication-guide
---

# Publishing a MIR 4 extension

Before distributing an extension:

1. choose a globally stable reverse-domain extension ID;
2. validate and lock every claimed target;
3. run explain, test, conformance, and dependency/conflict closure;
4. review the deterministic diff from the previous version;
5. build the developer archive twice and compare hashes;
6. publish the extension schema version, target bounds, digest, changelog, and known unavailable outcomes.

Do not describe a developer package as a Factorio mod or promise that MIR will emit its plan. The publisher owns its key and distribution custody; MIR release keys never sign third-party extensions.
