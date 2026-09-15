---
title: "MIR Extension Protocol"
status: current
applies_to: "MIR 4.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-09-15
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-extension-protocol
---

# MIR Extension Protocol

MEP V1 is the bounded, declarative route for third-party compatibility knowledge in MIR 4.0. It is a separately distributed developer preview, not part of the player ZIP.

An extension is a data-only envelope containing versioned fragments, target constraints, dependencies, conflicts, diagnostics, and a digest. It cannot supply callbacks, compiler context, Factorio prototypes, executors, SafetyKernel internals, migrations, or release credentials.

The supported developer workflow is:

```text
doctor -> init -> validate -> lock -> explain -> test -> package
                       \-> diff
                       \-> ci-init
v0 input -> migrate
F210 mod-data snapshot -> discover
```

All plans are read-only shadows. F210 discovery reads only the extension-owned `more-infinite-research.extension.v1` mod-data key. Player emission remains blocked behind the unchanged terminal emitter until a separately admitted transport cutover.

Start with [the developer guide](developer/first-extension.md), then read the [fragment reference](developer/mep-fragment-reference.md) and [publishing guide](developer/publishing-an-extension.md).
