---
title: F110 to F200 catalogue continuity fixture
---

This disposable two-stage fixture prepares one published Factorio 1.1.110 save from `more-infinite-research` 4.7.11003, then observes that exact save under the F200 MIR5 edition. It is a CONT13 input and gameplay witness design, not a native result, release qualification, or a general migration planner.

The source is `mir-fixture-mir5-f110-f200-transition` 0.1.0 with exactly Base 1.1.110, published MIR 4.7.11003 (`66C127D8BFC1919FA88F19D2D9B3047316A1B90401CAA05A6D05979B7A099D1E`), and the fixture. Its source profile is `tests/profiles/f110-f200-transition-published-f110-11110.json`; it pins the retained F110 engine SHA `B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1`.

The successor is 0.2.0 on Base 2.0.77 and MIR5 5.0.20000. Its profile pins the offline EA41 F200 candidate archive `CDC687538EEE4BB6E3E897057ACBA6DE51C74C164F8339D613D034BA952D89FD`; this is a frozen input only, not current-native or release acceptance. A later selected package must be rebound before execution.

The runner composes a stage directory with the stage wrapper and catalogue plus `fixture_control.lua` from `shared/control.lua` and `fixture_data_final.lua` from `shared/data-final-fixes.lua`. The source is a narrow `-F110PublishedCrossSource` run using the retained F110 server/two-closed-reload path; the successor consumes the resulting immutable save through the existing F200 `InputSavePath` route. The ordinary historical-native and historical-transition contracts are not changed.

The source earns exactly one real character-mining lab level. The other sixteen rows are explicitly labelled saved-state seeds. It carries a 42-percent player queue, a separate 27-percent suspended force, and an independently disabled foreign force. The successor must retain all 17 named rows and their unordered scalar/categorical prototype-effect vectors, mapping only the native inserter capacity effect from stack to bulk (`2/4` in both forms). It then finishes one actual successor mining lab and emits two read-only reload markers. Engine-specific aggregate force totals and unlisted contributions are deliberately not compared.
