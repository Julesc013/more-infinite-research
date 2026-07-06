# MIR Governance Manifests

The `.mir/` directory contains repo-governance records for the 3.x line. These
files are not part of the shipped Factorio mod; they make documentation,
compatibility claims, generated streams, module boundaries, fixtures, branch
policy, and Codex routing lintable.

The operating rule is:

```text
Every important thing has one canonical human doc and one canonical machine record.
```

Current manifests:

- `docs.yml`: registered documentation pages and source-of-truth ownership.
- `modules.yml`: prototype/module boundaries and mutation rules.
- `capabilities.yml`: capability lanes and their canonical docs.
- `claims.yml`: compatibility claim record locations and public claim rules.
- `streams.yml`: generated stream manifest location and stream policy.
- `fixtures.yml`: fixture groups and the claims or gates they validate.
- `branches.yml`: branch purposes, accepted changes, and backport rules.
- `agents.yml`: required reading and validation routes for Codex-style agents.
