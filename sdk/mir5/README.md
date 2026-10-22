# MIR SDK — candidate examples

This directory is developer-only. It contains two independently installable **example contracts**, not the MIR API implementation and not accepted native results. Their prototype IDs are new disposable example IDs, never replacements for historical MIR research.

Read the [API specification](../../spec/mir5/api.md). The proposed API must be implemented and qualified before these examples can load. Both use only its public module/remote interface. The sample metadata targets Factorio 2.1.23 and is not a claim of current engine installation or cross-target support.

- `examples/required/`: a required-MIR extension invokes the helper during its final-fixes round, demonstrating that no later MIR finalizer is necessary.
- `examples/optional/`: an optional extension explicitly handles absent MIR and missing capability. It must also load alone.

Package the contents of each example as its own named Factorio mod using the existing test harness. Do not ship either in MIR's player ZIP. Do not run an incomplete replacement on a valuable save.

Conformance includes native effect/output, two extensions together, duplicate IDs, invalid input, ownership isolation, unavailable capability, save/reload and actual joining clients. Exact test runner commands are to be recovered from the repository before execution, not invented here. The host layout tests supplied in this archive do not execute these examples.
