# MIR 3.2.2 C24 differential manual-review packet

- Candidate: C24
- Package source: `29f81addc0eec9b571afd6428c9e3529c4497a1b`
- Archive SHA-256: `8A08758EECEEE3A930DE58A36395DD011F9BC2FB69D214CCAFFC065276ECF8D8`
- Content SHA-256: `25E05F748E5B33748F16F78C66DDE4FD11CB48DB5F499BBE232668746981C87F`
- Factorio review runtime: `2.1.12.87038` (`EB29D1349C4B6067E75C0B6EFDF8E773649579CF2FAEA9297884020C26525F27`)

## Exact differential boundary

The approved C21-to-C24 package delta adds `prototypes/mir/runtime/planet_discovery_recovery.lua` and changes only `changelog.txt`, `info.json`, and `prototypes/mir/runtime/scripted_techs.lua`. It does not change technology prototypes, icons, locales, settings, costs, effects, recipe membership, science, prerequisites, or balance.

The exact C21 package was manually reviewed by Julesc013. Those observations may support differential review of unchanged visual and balance surfaces, but they do not by themselves assert that C24's new runtime repair and Py ordering behavior were manually observed.

## Candidate-bound automated observations

- Exact Factorio 2.1.8 Base and Space Age ZIP loads passed.
- Exact Factorio 2.1.12 Base and Space Age focused loads passed.
- All six direct 3.2.1-to-3.2.2 upgrade archetypes passed, including affected planet discovery.
- The synthetic late Py reconstruction fixture passed and retained valid sibling effects in order.
- The exact 15-mod Py 3.1 closure passed on Factorio 2.1.12 with `casting-gear` and its dangling unlock absent, all valid effects retained, and zero unexpected sanitation.
- The focused scripted-runtime disable/restoration configuration-change scenario passed on exact C24.
- Paired C21/C24 performance passed all governed lanes; the definitive full no-reuse campaign remains a separate release gate.

## Maintainer confirmation still required

The schema-2 attestation must not be created until Julesc013 explicitly accepts this exact C24 differential for the seven governed items: technology-tree visual, icon visual, locale fit/truncation, settings UX, save UI, human balance, and configuration-change give-item safety.
