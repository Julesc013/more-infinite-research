# Forking MIR

The source may be forked, but MIR's name, signatures, support claims, and release custody do not transfer automatically.

An honest successor should:

1. choose a new distribution namespace and schema domain where identity would otherwise be ambiguous;
2. preserve MIR's license notices and immutable historical evidence;
3. describe its own release identity, supported targets, support scope and any signing policy without implying MIR's authorization transfers;
4. run the applicable current build, API conformance, package-exclusion, native/save qualification and public-byte verification checks;
5. describe precisely which MIR claims were reproduced and which were not.

Do not reuse MIR signatures, claim an unperformed audit, or present preview/shadow behavior as stable. If a fork retains compatible public contracts, it should publish a bounded compatibility statement and migration horizon rather than implying shared governance.

The portable starting points are [Project continuity](docs/progress.md), [Development](docs/development.md) and the [specification index](spec/README.md). Historical MIR4 restore/seal workflows retain their original scope; they are not prerequisites for a current MIR5 fork.
