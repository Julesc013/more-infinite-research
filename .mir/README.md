# MIR Transitional and Historical Governance Namespace

The package-excluded `.mir/` directory retains typed governance, compatibility, stream, fixture, branch, release, and generated-view records accumulated through MIR 3 and MIR 4. It is a compatibility namespace during the MIR 4 authority migration, not a blanket current-authority claim and never part of a player ZIP.

The operating rule is:

```text
Every current fact has one writable authority; historical records remain immutable evidence; generated projections are never edited by hand.
```

Current manifest entry points:

- `docs.yml`: registered documentation pages and source-of-truth ownership.
- `modules.yml`: prototype/module boundaries and mutation rules.
- `capabilities.yml`: capability lanes and their canonical docs.
- `compatibility.yml`: compatibility claim record locations and public claim rules.
- `streams.yml`: generated stream manifest location and stream policy.
- `fixtures.yml`: fixture groups and the claims or gates they validate.
- `branches.yml`: branch purposes, accepted changes, and backport rules.
- `agents.yml`: required reading and validation routes for Codex-style agents.
- `control/paths.yml`: compatibility path registry while final authorities move to their declared repository roots.

The current MIR 4.x work programme is `spec/programmes/mir4-4x-operating-programme-v1.json`. The MIR 4.0 pre-freeze programme under `.mir/releases/waves/mir4-r0/` is a completed historical execution record. MIR 3 release records remain immutable history. Root `todo.md` and other generated views must be regenerated from these authorities through the supported toolchain.

