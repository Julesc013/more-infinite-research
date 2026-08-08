# MIR 3.2.5 development playtest revision 4

This is the latest playtest-green and breadth-green development build. It is not a release candidate or published release.

## Identity

- Synchronized `dev`: `489b62fda979c5192ddbb8294c27a3886f6ba13e`
- Source tree: `0d3fc58d69eed64bcb2199a051f9fc9f6a6c9c30`
- Package source: `5264ab2285b56ac2a79dc1bc99724554fb558c7f`
- Archive SHA-256: `AF3F4D6AFF58B098D6729FE31B039C47497988E7515D1055F4C5C54D85B5CDBD`
- Normalized content SHA-256: `A313E8A3E377A099FCB6E8266A3EDBDF5AEF9D77CF777B041472C772C6448877`
- Size: 1,055,804 bytes
- Entries: 301
- Factorio: 2.1.12, build 87038

## What to exercise

Revision 4 adds a bounded research-cost compatibility proposition, typed proof, terminal disposition, and privacy-bounded support record. Please focus on:

1. Clean Base and Space Age starts with only this ZIP enabled.
2. Fixed, linear, exponential, and hybrid research costs, including native owners and absence of duplicate owners.
3. Technology tooltips and any visible diagnostics or support output related to the research-cost model.
4. Configuration changes while an infinite research is active: selection, queue, completed levels, completed science-unit work, and unrelated force state must survive.
5. A second save/reload after configuration change; it must be idempotent and must not perform a force-wide effect reset.
6. An upgrade of a copied 3.2.3 save, retaining before/after saves and logs.

For any defect, retain the exact ZIP hash, `factorio-current.log`, `mod-list.json`, `mod-settings.dat`, before/after saves, and a short observation note.

## Governance

C32 is unassigned and MIR 3.2.5 remains `planned`. No 2.5.5 authority exists, MIR 3.3 is not admitted, and the published archives directly under `dist/` remain unchanged.
