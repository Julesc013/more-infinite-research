# MIR 3.2.5 development playtest revision 5

This is the latest playtest-green and breadth-green development build. It is not yet a release candidate or published release.

## Identity

- Synchronized `dev`: `a3bfbc4524b52cede425900e775384eb9c1fc4b3`
- Source tree: `a038ba1bcce347c53ee906d466279854c5a8d485`
- Package source: `90ff29e76b71d8fcb907eca37bc8057cf2f43937`
- Archive SHA-256: `AC81CAD1AC37F20E27A46BFAD243611DB251CACCF52E1AB4DA5D06CFDAA11ADF`
- Normalized content SHA-256: `1A2A37380FDE8EA0C260F90414ECB2BF70314341369D816FDD74D59B50535A7D`
- Size: 1,056,249 bytes
- Entries: 301
- Factorio: 2.1.12, build 87038

## What changed since revision 4

Revision 5 completes the essential 3.2.5 research-cost correctness contract: algebraic positivity and monotonicity proof, explicit parser and numeric limits, exact 3.2.3 default vectors, deterministic ownership dispositions, shipped-feature Factorio 2.0 dispositions, and mandatory first/second reload evidence for all five direct upgrades.

## What to exercise

1. Clean Base and Space Age starts with only this ZIP enabled.
2. Fixed, linear, exponential, and hybrid research costs at their first controlled level and several later levels.
3. Native, MIR-created, adopted, transferred, removed, and ambiguous owner behavior; no modifier may have duplicate effective owners.
4. Configuration changes while infinite research is active. Selection, queue, completed levels, completed science-unit work, and unrelated force state must survive without a force-wide effect reset.
5. Save/reload twice after the change. The second reload must be idempotent.
6. Upgrade copied 3.2.3 Base and Space Age saves, retaining before/after saves and logs.
7. Very large but valid cost settings and visibly invalid/out-of-envelope settings; unsafe values must fail closed rather than overflow or silently drift.

For any defect, retain the exact ZIP hash, `factorio-current.log`, `mod-list.json`, `mod-settings.dat`, before/after saves, and a short observation note.

## Governance

C32 remains unassigned and MIR 3.2.5 remains `planned`. No 2.5.5 authority exists, MIR 3.3 is not admitted, 3.2.4/C31 remains superseded-unpublished, and the governed archives directly under `dist/` remain unchanged.
