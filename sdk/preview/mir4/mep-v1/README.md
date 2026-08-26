# MIR Extension Protocol V1 preview

This self-contained, offline developer preview supplies minimal, all-fragment, and unavailable templates; positive, conflict, unavailable, migration, and F210 discovery examples; and eleven commands: init, doctor, validate, lock, diff, discover, explain, test, package, migrate, and ci-init.

Start with docs/reference/mir4-first-extension.md. The F210 collector now discovers extension-owned mod-data snapshots, validates envelopes, resolves dependency/conflict closure, and explains shadow plans. It remains package-excluded and read-only; F210 emission/admission is still blocked behind the unchanged terminal emitter.