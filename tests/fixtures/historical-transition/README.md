---
title: Historical published-save transition fixture
---

This disposable fixture exercises one named character-mining-speed research, its earned native effect and the saved state supported by each selected engine. It does not establish complete catalogue, modpack, multiplayer, performance or release qualification. The shared Lua files are unchanged by the added 4.7.3 input selections.

The original [metadata](metadata.json) retains the exact 4.7.2 predecessors and the separate F018/1.8.0 predecessor. Its profiles, original saves and native receipts keep their own identities. F018 remains experimental/best effort; this fixture does not create an additional stable F018 campaign.

The separate [4.7.3 metadata](metadata-473-f013-f016.json) selects only the published F013–F016 archives already identified in the [migration-origin inventory](../../../spec/inventory/migration-origins.json). Its explicit `predecessor_release` selects an exact version/hash tuple; another patch, target or archive is refused. This is prepared input selection, not evidence that an engine has loaded it or a save has migrated.

Use the matching published-source profile:

- [F013 / 0.13.20](../../profiles/historical-transition-473-published-f013.json)
- [F014 / 0.14.23](../../profiles/historical-transition-473-published-f014.json)
- [F015 / 0.15.40](../../profiles/historical-transition-473-published-f015.json)
- [F016 / 0.16.51](../../profiles/historical-transition-473-published-f016.json)

Prepare the existing six-member fixture projection for the selected stage. `Get-HistoricalTransitionFixtureTarget` reads the explicit metadata, and `ConvertTo-HistoricalTransitionFixtureTargetLiteral` supplies `target-literal.lua`. The four shared Lua files remain exact source bytes; `info.json` uses the selected engine family, fixture version and exact stage MIR dependency. The existing `Assert-HistoricalTransitionFixtureArchive` checks all six members, the literal and metadata before admission. Keep each projection and its resulting archive hash separate from earlier runs.

The native owner then uses `tools/Invoke-NativeFixture.ps1` with the selected direct `ArchiveLibrary`, exact `FactorioBin`, matching `ProfilePath`, projected `FixtureSources`, `CaseName=historical-transition`, `HistoricalTarget`, `HistoricalTransitionStage=published`, the explicit `HistoricalTransitionFixtureMetadataPath` above and the exact published `ExpectedMIRArchiveSha256`. The generic runner remains responsible for resource admission, original controls and save-byte preservation. These selections contain no dependency copies and grant no library ownership or native assignment.

The source stage must create its own actual 4.7.3 world, complete the one source laboratory research, save and pass the existing two read-only cold reloads. A previously passing 4.7.2 source world is not relabelled as a 4.7.3 source. Keep the protected original save, package, engine, profile, metadata, fixture and controller identities together.

For a later selected MIR5 successor, use the same metadata with `HistoricalTransitionStage=mir5`, the protected source's `InputSavePath` and `ExpectedInputSaveSha256`, and a separately frozen MIR5 package/hash. Reuse a matching MIR5 edition profile only after checking its actual version and fixture selection. This preparation does not pin or qualify a moving candidate.

F013/F014 retain their existing preservation-only successor mode because their native research-state contract differs from later engines. F015/F016 retain the real successor-lab and 42% partial-work checks. No newer queue API or foreign-force witness is invented for these targets; their existing data, effect, laboratory and cold-reload predicates remain unchanged. Missing engine or save inputs remain unverified rather than counted as a pass.
