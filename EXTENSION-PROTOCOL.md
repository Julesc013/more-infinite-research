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

Start with [the developer guide](docs/developer/first-extension.md), then read the [fragment reference](docs/developer/mep-fragment-reference.md) and [publishing guide](docs/developer/publishing-an-extension.md).
