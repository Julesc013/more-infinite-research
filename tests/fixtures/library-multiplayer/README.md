# Library multiplayer fixture protocol

Start this fresh selected F200/F210 Base or separate F210 Space Age world, then connect exactly two real clients whose actual `LuaPlayer.locale` values report `en` and `de`. Initial unchanged locales do not require a locale-change event. Wait for the `rejoin-ready` marker, disconnect and reconnect both clients, then wait for `restart-ready` and the requested `mir5-library-multiplayer-restart` save. Restart the host from that save, reconnect both clients again, and wait for `completed` plus `mir5-native-complete`.

The original Base selections admit F200 base2.0.77/MIR5.0.20000 and F210 base2.1.23/MIR5.0.21000. These F210 selectors do not enable Space Age. Their 7168 MiB combined session ceiling is a conservative resource-admission budget of one 2048 MiB owned server, two 2048 MiB owned GUI clients, and 1024 MiB watchdog/fixture reserve. It is neither a measured peak nor a performance or native-acceptance result.

The separate F210 API-client selection admits one additional exact closure: the same Library members plus the independently packaged `mir-fixture-mir5-api-alpha` and `mir-fixture-mir5-api-beta` consumers at 0.1.0. It excludes partial consumer selections, changed versions, extra mods, and the beta physical-production fixture. The existing clients must each emit one alpha and one beta `on_load` marker after every initial join, rejoin, and host-restart join; the session reader uses only the new bytes of that client’s own log, whether Factorio appends or replaces the file. This is a read-only runtime-query route, not a cable-production qualification.

The [retained A8 API-client selection](../../profiles/library-api-consumers-current-standalone-f210-2123.json) separately pins the `575e`/`ba8` player tree and F210 archive `A8D0A459`, retaining the same standalone 2.1.23 engine, observer, two consumers and Base-only protocol. Its exact archive hashes are independent of the [earlier D5/2ABA selection](../../profiles/library-api-consumers-standalone-f210-2123.json), which remains unchanged. The [A8 Base and Space Age native chain](../../../spec/evidence/library-api-575e-native-chain-r01.json) records the actual two-client initial/rejoin/restart, laboratory, saved-state and rendered-view observations for its frozen controllers. Those results retain source `575e` / player tree `5ba` and do not qualify the later private-credit Library correction. Neither Base selection enables Space Age; the 7168 MiB session budget remains an admission estimate rather than a measured peak.

From the reviewed frozen checkout, the native owner supplies its existing direct `$ArchiveLibrary` and verified standalone `$FactorioBin` paths, then runs this typed invocation with a fresh output directory. The library must supply the selection's exact current MIR, observer and consumer archives through the existing owned-slot custody workflow; preserve and restore any previous archive slot as well as the runner-owned mod-list/settings controls. The wrapper does not select a different MIR package on the owner's behalf. The explicit 7168 MiB argument is required; the wrapper's generic 8192 MiB default is not this selection's budget.

```powershell
$apiSession = @{
  ArchiveLibrary = $ArchiveLibrary
  FactorioBin = $FactorioBin
  ProfilePath = 'tests/profiles/library-api-consumers-current-standalone-f210-2123.json'
  FixtureSources = [string[]]@(
    'tests/fixtures/library-multiplayer'
    'tests/fixtures/active-mods-observer'
    'tests/fixtures/api-alpha'
    'tests/fixtures/api-beta'
  )
  ExpectedMIRArchiveSha256 = 'A8D0A4590154F3106E59BDB269F1AEB3ED8CC523F18F00ED7D76DC89059F5B8D'
  OutputRoot = 'build/tmp/library-api-current-a8-r01'
  FixtureCase = 'library-multiplayer'
  SessionExpectedPeakMemoryMiB = 7168
  RepoRoot = (Resolve-Path '.').Path
}
.\tools\Invoke-MultiplayerFixture.ps1 @apiSession
```

The distinct [retained A8 Space Age API-client selection](../../profiles/library-api-consumers-current-space-age-standalone-f210-2123.json) uses the same A8 MIR archive, standalone engine, observer and consumers, with Library fixture metadata 0.2.0. Its exact ten-mod closure adds `elevated-rails`, `quality`, `recycler` and `space-age`, all 2.1.23. Missing or extra mods, changed versions, crossed Base/Space Age markers and the beta physical-production fixture are rejected. The Base fixture remains 0.1.0; its frozen selections and earlier receipts remain separate inputs.

Use the same direct-library custody prerequisites above and a fresh output directory for this separate invocation. Its explicit 8192 MiB admission budget must agree with the profile and session. Clients use 1280×720 low-graphics functional rendering (`--force-graphics-preset low --video-memory-usage low`). Neither that budget nor successful host controls establish a measured peak, graphical acceptance or performance result.

```powershell
$spaceAgeApiSession = @{
  ArchiveLibrary = $ArchiveLibrary
  FactorioBin = $FactorioBin
  ProfilePath = 'tests/profiles/library-api-consumers-current-space-age-standalone-f210-2123.json'
  FixtureSources = [string[]]@(
    'tests/fixtures/library-multiplayer'
    'tests/fixtures/active-mods-observer'
    'tests/fixtures/api-alpha'
    'tests/fixtures/api-beta'
  )
  ExpectedMIRArchiveSha256 = 'A8D0A4590154F3106E59BDB269F1AEB3ED8CC523F18F00ED7D76DC89059F5B8D'
  OutputRoot = 'build/tmp/library-api-space-age-current-a8-r01'
  FixtureCase = 'library-multiplayer'
  SessionExpectedPeakMemoryMiB = 8192
  RepoRoot = (Resolve-Path '.').Path
}
.\tools\Invoke-MultiplayerFixture.ps1 @spaceAgeApiSession
```

The new private-credit selections pin source `8260bc8f` / player tree `50583733` and F210 archive `005D4206`, with fixture 0.3.0 on the same standalone 2.1.23 engine and independent API consumers. The [Base selection](../../profiles/library-api-consumers-private-credits-standalone-f210-2123.json) admits exactly six mods and 7168 MiB; the [Space Age selection](../../profiles/library-api-consumers-private-credits-space-age-standalone-f210-2123.json) admits exactly ten mods and 8192 MiB. Space Age retains low-graphics 1280×720 functional rendering. These are prepared inputs without native acceptance; the new mode is separate from the completed A8 runs above.

After all four profiler observations and the 60-tick host-restart screenshot grace, fixture 0.3 uses only the public browser interface to search each of the four exact private credit IDs in All and External for both connected clients. Before its private queries, each client must see selected, enabled Gear research in All and native Automation in External, preventing an empty scope from passing the exclusion check. The private queries require empty result/detail views and disabled native-open actions. The probe compares native research/queue/effects, each holder's level/researched/enabled/visibility fields and Automation's native state before and after, then restores both personal views and their MIR family filter. It reads no MIR storage, imports no MIR module and grants no research. The probe adds no profiler samples, screenshots or timing ticks; its native GUI-state assertions are separate from rendered PNG evidence. Only the completed marker contains its typed `private_credit_visibility` witness.

Use the same direct-library archive-slot custody and restoration requirements above, with the exact new MIR package and a fresh output directory. This Base invocation requires 7168 MiB explicitly:

```powershell
$privateApiSession = @{
  ArchiveLibrary = $ArchiveLibrary
  FactorioBin = $FactorioBin
  ProfilePath = 'tests/profiles/library-api-consumers-private-credits-standalone-f210-2123.json'
  FixtureSources = [string[]]@(
    'tests/fixtures/library-multiplayer'
    'tests/fixtures/active-mods-observer'
    'tests/fixtures/api-alpha'
    'tests/fixtures/api-beta'
  )
  ExpectedMIRArchiveSha256 = '005D420671270306155CB4AC25E9CF77541202DFA16B206DCC016237619C9AA2'
  OutputRoot = 'build/tmp/library-api-private-credits-005d-base-r01'
  FixtureCase = 'library-multiplayer'
  SessionExpectedPeakMemoryMiB = 7168
  RepoRoot = (Resolve-Path '.').Path
}
.\tools\Invoke-MultiplayerFixture.ps1 @privateApiSession
```

For the separate Space Age run, select `tests/profiles/library-api-consumers-private-credits-space-age-standalone-f210-2123.json`, set `SessionExpectedPeakMemoryMiB = 8192`, and choose a fresh Space Age output directory. Keep the four fixture source directories and 005D MIR hash. Both budgets are admission ceilings, not measured peaks; the wrapper rejects mismatched profile, package or budget before launching the session.

The four latency observations are emitted directly to each executing process's native log as `[MIR5_LIBRARY_PROFILE] first_open`, `search`, `refresh` and `reopen`, followed by the engine-rendered profiler. Saved state and JSON witnesses contain only deterministic completion flags for those labels. Read the actual native log records to qualify timings; flags, profiler object identities and host mocks are not measured latency. No profiler value selects a gameplay or fixture-state transition.

The control requests ten GUI screenshots under `script-output/mir5-library-multiplayer/`: Availability, initial personal view, settled initial view, rejoin and host restart for each client. The initial Base Availability view contains exactly two terminal Space Age requirement explanations. The separate Space Age view instead requires the single `research_lab_productivity` native-owner row and validates the actual `research-productivity` technology's sole `laboratory-productivity` +0.10 effect. Availability stays open for 60 ticks before ordinary personal views replace it. After the original initial captures, the same roots, queries and native state are held for 60 ticks before the settled pair is requested, without reopening the Library. A further 60 ticks lets that pair render before `rejoin-ready` permits client disconnection. This separates a persistent layout defect from a transient initial capture; it does not declare either image correct. Screenshots become rendering evidence only after external PNG readback confirms the files; a headless request is not a rendering result.

After the initial personal views are open, the fixture keeps their public browser root and query objects, marks only the four named science-pack prerequisites researched, and queues two real levels of `recipe-prod-research_gears-1`. Its fixture-local `settings-updates.lua` reduces only that stream’s count and time so two actual lab completions can be observed within the bounded disposable world; it does not qualify ordinary cost or time tuning. The empty lab receives one of each named pack initially, then receives one more of each only after the first actual completion and its level-two/one-queued/UI witnesses. This staged fixture feeding keeps the total at two per named pack. The earlier all-at-once run stopped short of its second completion; the separate staged run40133428618 completed both, without establishing the earlier failure's cause. The control requires public force queue lengths 2→1→0 plus native started/finished events, `by_script == false`, level three, the resulting +20% iron-gear-wheel productivity, and zero remaining packs before it preserves the post-lab snapshot.

The Space Age variant additionally requires the authored gear definition's two +0.10 effects for `casting-iron-gear-wheel` and `iron-gear-wheel`, then observes +20% on both recipes after the same two actual lab completions. Its casting productivity must be zero initially and remain zero on the separate foreign force. It keeps the same four science packs, staged feeding and fixture-only cost/time acceleration; this does not establish ordinary Space Age tuning or physical casting output.

The fixture then queues and cancels one third level through `LuaForce.cancel_current_research`, requiring the native cancellation callback and no third laboratory completion. It creates a separate foreign force and requires that its initial gear level/productivity and both already-open player views remain independent. It never imports MIR internals, reads MIR storage, or synthesizes native events. The rejoin and host-restart stages still verify the stored post-lab witness and all ten client-local captures. The completed native session from run40133428618 retains its original eight-capture protocol and separate initial German clipping finding; these added captures and the separate Space Age variant require their own exact-input execution.
