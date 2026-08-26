# Forking MIR

The source may be forked, but MIR's name, signatures, support claims, and release custody do not transfer automatically.

An honest successor should:

1. choose a new distribution namespace and schema domain where identity would otherwise be ambiguous;
2. preserve MIR's license notices and immutable historical evidence;
3. publish its own maintainer keys, trust policy, target registry, support policy, and release ledger;
4. run the full offline restore, conformance, package-exclusion, target qualification, and public-byte verification suites;
5. describe precisely which MIR claims were reproduced and which were not.

Do not reuse MIR signatures, claim an unperformed audit, or present preview/shadow behavior as stable. If a fork retains compatible public contracts, it should publish a bounded compatibility statement and migration horizon rather than implying shared governance.

The portable starting points are [Project continuity](PROJECT-CONTINUITY.md), [Maintainer handoff](MAINTAINER-HANDOFF.md), and the generated documentation reference matrix.
