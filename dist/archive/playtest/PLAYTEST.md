# MIR 3.2.5 C32 candidate playtest

This is immutable development playtest revision 5 promoted without byte changes to candidate C32. It is candidate-qualified and ready for exact-hash maintainer playtest. It is not sealed or published.

## Identity

- Candidate: `C32`
- Release state: `candidate-qualified`
- Package source: `a3bfbc4524b52cede425900e775384eb9c1fc4b3`
- Package-source tree: `a038ba1bcce347c53ee906d466279854c5a8d485`
- Qualification/governance `dev`: `c3daa7c260cb911946d1c30af1391b2ccf12a231`
- Qualification tree: `12eb78edf5d985616114e594d441080aa3557dea`
- Pull request: `54`
- Archive SHA-256: `AC81CAD1AC37F20E27A46BFAD243611DB251CACCF52E1AB4DA5D06CFDAA11ADF`
- Normalized content SHA-256: `1A2A37380FDE8EA0C260F90414ECB2BF70314341369D816FDD74D59B50535A7D`
- Size: 1,056,249 bytes
- Entries: 301
- Factorio: 2.1.12, build 87038

## Automated qualification

- Fresh candidate campaign: 135/135 executed, zero failures or incomplete rows.
- Exact Base and Space Age ZIP loads passed.
- Five direct 3.2.3 upgrade archetypes, including first and second reloads, passed.
- All sixteen research-cost configuration transitions passed.
- Governed ecosystem and paired ten-lane performance campaigns passed.
- Latest exact PR head passed Branch Policy, Emergency Package, all eight workers, and deterministic aggregate import (8 imported; zero failed, missing, rejected, duplicate, or ignored).
- Synchronized merged `dev` passed the eight-row fast admission fresh, rebuilt the exact archive twice, and passed its own post-merge hosted Branch Policy, Emergency Package, and MIR aggregate (8 imported; every error list empty).

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

## Pending human gate

Use `interactive-review/C32-AC81CAD1/` for isolated Base and Space Age profiles, pending worksheets, screenshots, and saves. Every manual item remains pending until you record it.

Human acceptance, protected no-reuse qualification, sealing, `main`, tagging, publication, and public-byte verification have not occurred. No 2.5.5 authority exists, MIR 3.3 is not admitted, and 3.2.4/C31 remains superseded-unpublished.
