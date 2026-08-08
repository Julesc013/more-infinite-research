# MIR 3.2.5 development playtest revision 3

This is a development-test build, not a release candidate or published release.

## Identity

- Source commit: `b1144889386cf8bc5e7561bf6399d1127cfa74cb`
- Source tree: `b2671260c6fb84b75dbd86ad43e9351842cb91bb`
- Archive SHA-256: `79965DD6167488013CEEE414897C4F00350B6FE541F4459B80D49C234DBDF208`
- Normalized content SHA-256: `489DFFB3C5998773B13256DB2298495FB97CE87F8C45C0A916E062DB1475DE0F`
- Size: 1,051,537 bytes
- Entries: 299
- Factorio: 2.1.12, build 87038

## Install

Copy `more-infinite-research_3.2.5.zip` into the Factorio mods directory. Remove or disable other MIR versions and do not leave an unpacked MIR source directory beside it.

## Suggested playtest

1. Start a clean Base game with only this ZIP and inspect startup logs, settings, and the technology tree.
2. Start a clean Space Age game and repeat the inspection.
3. Exercise a visible fixed, linear, exponential, and hybrid research-cost example. Check the first controlled level, next-level cost, formula display, native-owner behavior, and absence of duplicate owners.
4. Begin an infinite research, record level and fractional progress, change its curve parameters, then reload. Confirm selection, queue, completed work, and unrelated technology effects survive, and no global force reset occurs. Save and reload once more to confirm idempotence.
5. Upgrade a copy of a 3.2.3 save to this exact ZIP and retain before/after saves and `factorio-current.log`.

Please retain the exact ZIP hash, `factorio-current.log`, `mod-list.json`, `mod-settings.dat`, before/after saves, and a short observation note for any defect.

## Governance

C32 is unassigned and MIR 3.2.5 remains `planned`. No 2.5.5 authority exists, MIR 3.3 is not admitted, and `dist/` is unchanged.
