# Space Is Fake SIF-01 continuation fixture

This private native packet qualifies the two retained continuation identities
`research-speed-7` and `weapon-shooting-speed-7` with Space Is Fake enabled.
It uses only the exact archived closures below:

| Target | Engine | Space Is Fake | Required companion archives |
| --- | --- | --- |
| F200 | 2.0.77 | 1.0.60 (`860F2048A7E6F4C2ECD1A9CECA6ECDD340ECF797773EC582A6E60FFE6F8D87AC`) | cr-commons 1.0.27 (`6F3622AE6270F9B365A9E2E07FA5E07B61B2BBFCAB3A4D930CC410EBDEB63B92`) |
| F210 | 2.1.23 | 1.0.78 (`3B5F2A381ADF1D9AECF048293E20035963A528720FBDC148CCC2B0418049FF13`) | cr-commons 1.0.33 (`378D3114B09C872358088B33500BC4AB0B9B9EFD9E5650DBEA0E87B5914C29BB`), cr-extras 1.0.10 (`3AB74877E49FB245E62593B669EB4D5C762207C047CA6F70E4D0CC9B67DF0225`) |

The current F210 selection uses independently filed cr-extras 1.0.10 only to replace the engine-invalid input archive; it has not received a native result or qualification claim. The retained 1.0.01 MIR-absent failure below remains historical adverse evidence with its original archive identity and source references.

SIF's archived `data-updates.lua` removes `space-science-pack` from existing
technology units. Its `technology.lua` retires the space-science prerequisite.
Published 4.7.2 source `bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1` separately
applied the same retirement in its science policy. The fixture contract records
the two published continuation rows and all eight current science-policy
vectors after that retirement. It does not import MIR code or derive an oracle
from a candidate package.

## Published configured predecessor oracle

The published and successor contracts are deliberately separate. In the
configured predecessor, the published continuation carries the active Space
Age vector and SIF removes only `space-science-pack`. Consequently
`research-speed-7` has eleven ordered science inputs: automation, logistic,
chemical, production, utility, military, agricultural, metallurgic,
electromagnetic, cryogenic and promethium. Its exact ordered prerequisites on
both targets are `research-speed-5`, `utility-science-pack`,
`research-speed-6`, automation, logistic, chemical, production, military,
agricultural, metallurgic, electromagnetic, cryogenic and promethium science.

`weapon-shooting-speed-7` retains the Base five science inputs (automation,
logistic, chemical, military and utility) and these exact ordered
prerequisites on both targets:

- `weapon-shooting-speed-7`: `weapon-shooting-speed-5`,
  `utility-science-pack`, `weapon-shooting-speed-6`,
  `automation-science-pack`, `logistic-science-pack`,
  `chemical-science-pack`, `military-science-pack`.

The predecessor uses a real `biolab`, the accepted native laboratory for the
full Space Age science vector. The successor also uses that laboratory so the
source and successor consumption observations share a real lab identity.
The exact installed F200 2.0.77 upstream
`data/space-age/prototypes/entity/entities.lua:1674`
(`7825FCB0EF10BD5112A0018BBC67CD134DD9CBDB766BC1E612F1901045BB2DCC`) and
F210 2.1.23 counterpart at line 1788
(`F77F2552C4059326FFF18357DDE6EE34200F66079CC70BFA3C6B46AC2353E616`) both
declare `science_pack_drain_rate_percent = 50` and four module slots. The
fixture preflights that native drain, installs no modules, and uses a count of
two at one second. Thus each full research consumes one unit of each one-unit
science ingredient through the real Biolab's 50% drain. Neither archived SIF
package writes `data.raw.lab.biolab` or `science_pack_drain_rate_percent`.

The source records are the Base and Space Age published rows in
`spec/inventory/modern-f200-470.json`
(`BF285A56864491DE95A6DF739586A1F6859D320EBE620E5E8615FA37DEA9A2D4`,
profiles `base-f200` and `space-age-f200`) and
`spec/inventory/modern-f210-470.json`
(`C37027F17D4F02C50C664739B242D62E29AAE0C68079450FCBA95499DC7EFB79`,
profiles `base-f210` and `space-age-f210`). The Space Age rows provide the
full twelve-pack research vector; the Base rows provide the unchanged
weapon vector and the ordinary prerequisite anchors. The independent F200
continuation capture
`tests/fixtures/native-modded-continuations-f200-captured-facts.json`
(`B437E5AF9DD51619DB4D8ABAF8C85FA0A25A93F4BA86ADB6EAE4A54DED27940A`)
records those Base anchors only; it is not treated as the active SIF closure.

The exact published source is commit
`bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1`. Its defaults
`source/prototypes/mir/settings/defaults.lua`
(`95b96cf50093cd4eb522cec4f419b8f879ed69c5`) give research speed
`science_packs="inherit"` and `add_science_packs="all"`, while weapon speed
adds military and space only. Its native continuation qualifier
`source/prototypes/mir/planner/base_continuations/qualify.lua`
(`f106053c49fd1a6aa04f9d5ab8c44e2247819723`) appends those admitted inputs
before selection; `pack_registry.lua`
(`b5949681071c1cef8b342bf233ab1e024fe70f96`) enumerates active lab inputs.
`policy_authority.lua` (`a518354229b69a04d03ce231968abfa3ecec24bf`)
declares the sole SIF exclusion, `space-science-pack`, and
`science_selector.lua` (`717a3c47895bb48187a1aa76a3e4bb5bc2e4b34f`)
removes only excluded roles. `science_selection_policy.lua`
(`a905ee4f675895e90a3f3426624bb1d7d290de03`) supplies the pinned policy
vector machinery. These are source provenance only; the fixture's predecessor
values come from the independent published inventories above.

The archived SIF packages contain no direct
`research-speed-7` or `weapon-shooting-speed-7` edit.  Both
`data-updates.lua` members have SHA-256
`6676A22AD0A16A18B3CB8F94D72C195DFCCA663690FAF1AA2FD40499C2057DD3` and
remove `space-science-pack` from technology ingredients generically.  The
F200 `prototypes/technology.lua` member is
`35BF4615D30E81EF39975C8E278EFA44A57919CF13C7928A9A0DE9E4532549AE`; the
F210 member is
`F07B8B992B67022967E5C2DD6D65C6C07FA19665A53940DBF74E20A617002C3C`.

## MIR5 successor policy oracle

The active MIR5 Space Age continuation override supplies the full twelve-pack
research vector and six-pack weapon vector before the science policy runs.
Research speed already carries every official role. After the finite SIF rule
removes `space-science-pack`, all eight policy values therefore retain its
eleven ordered successor inputs. Weapon shooting speed carries only the Base
roles and space: configured, space, Space Age progression and mod progression
retain five; space-and-promethium appends promethium; official progression
appends production; and all-official/all append production plus the five Space
Age packs. These are policy additions to the retained source order.

The successor's prerequisite record remains a separate fixture contract. It
requires the research row's 13 non-space prerequisites in every policy and
the weapon row's Base seven plus the named additions for the four policy
selections that append a pack. Those selections are
space-and-promethium, official-progression, all-official, and all. The narrow
SIF correction filters the two owned rows'
pre-authored space prerequisite; it is needed because continuation
construction initially includes the full source vector as prerequisites. The
fixture deliberately rejects the former six-pack research and three-anchor
successor oracle before it accelerates either row.

This successor expectation is grounded in the current authored Space Age
override, `source/compatibility/modern_catalogue/space_age.lua`, and its
continuation construction in `source/research/modern.lua`; the published
predecessor remains grounded in the independent inventories and pinned 4.7.2
source described above. It is not inferred from a candidate engine result.

Each target has a published 4.7 configured-policy core (`0.1.0`) and a MIR5
successor core (`0.2.0`) with the same fixture mod name, so its owned saved
state survives the genuine package upgrade. The eight tiny policy selectors
only change the existing startup policy default after checking the setting
contract. Their `info.json` files carry target-specific dependency identities.

## Raw-Git staging map

The native controller materializes a self-contained fixture source only in its
owned temporary staging area. For the selected fixture commit `C`, each
source below means `git show C:tests/fixtures/sif-science-retirement/<source>`;
the left side is the destination member in the staged fixture source.

| Destination | Git source |
| --- | --- |
| `f200/published/contract.lua` | `shared/core/contract.lua` |
| `f200/published/data-final-fixes.lua` | `shared/core/data-final-fixes.lua` |
| `f200/published/control.lua` | `shared/core/control.lua` |
| `f200/mir5/contract.lua` | `shared/core/contract.lua` |
| `f200/mir5/data-final-fixes.lua` | `shared/core/data-final-fixes.lua` |
| `f200/mir5/control.lua` | `shared/core/control.lua` |
| `f210/published/contract.lua` | `shared/core/contract.lua` |
| `f210/published/data-final-fixes.lua` | `shared/core/data-final-fixes.lua` |
| `f210/published/control.lua` | `shared/core/control.lua` |
| `f210/mir5/contract.lua` | `shared/core/contract.lua` |
| `f210/mir5/data-final-fixes.lua` | `shared/core/data-final-fixes.lua` |
| `f210/mir5/control.lua` | `shared/core/control.lua` |
| `f200/policy-configured/settings-updates.lua` | `shared/selectors/configured/settings-updates.lua` |
| `f210/policy-configured/settings-updates.lua` | `shared/selectors/configured/settings-updates.lua` |
| `f200/policy-space/settings-updates.lua` | `shared/selectors/space/settings-updates.lua` |
| `f210/policy-space/settings-updates.lua` | `shared/selectors/space/settings-updates.lua` |
| `f200/policy-space-and-promethium/settings-updates.lua` | `shared/selectors/space-and-promethium/settings-updates.lua` |
| `f210/policy-space-and-promethium/settings-updates.lua` | `shared/selectors/space-and-promethium/settings-updates.lua` |
| `f200/policy-space-age-progression/settings-updates.lua` | `shared/selectors/space-age-progression/settings-updates.lua` |
| `f210/policy-space-age-progression/settings-updates.lua` | `shared/selectors/space-age-progression/settings-updates.lua` |
| `f200/policy-official-progression/settings-updates.lua` | `shared/selectors/official-progression/settings-updates.lua` |
| `f210/policy-official-progression/settings-updates.lua` | `shared/selectors/official-progression/settings-updates.lua` |
| `f200/policy-mod-progression/settings-updates.lua` | `shared/selectors/mod-progression/settings-updates.lua` |
| `f210/policy-mod-progression/settings-updates.lua` | `shared/selectors/mod-progression/settings-updates.lua` |
| `f200/policy-all-official/settings-updates.lua` | `shared/selectors/all-official/settings-updates.lua` |
| `f210/policy-all-official/settings-updates.lua` | `shared/selectors/all-official/settings-updates.lua` |
| `f200/policy-all/settings-updates.lua` | `shared/selectors/all/settings-updates.lua` |
| `f210/policy-all/settings-updates.lua` | `shared/selectors/all/settings-updates.lua` |

The four target/stage core directories and sixteen target/policy selector
directories intentionally retain only their target-specific `info.json` bytes.
They are not alternate Lua authorities.

The dispatched packet runs all eight MIR5 policy profiles on both targets at
data stage. Core preflight checks each full row before it changes only the two
disposable research count/time fields to two units/one second. The configured
policy additionally runs two real published labs, then seeds detached saved
progress of 42% on research speed and 27% on weapon shooting speed. It checks
that state through two source cold reloads and again immediately after MIR5
configuration, before either successor lab is queued. The two actual successor
labs resume the partial levels, save, and observe two cold reloads. Source full
research consumption remains exact at one unit per input; the partial successor
work records native before/after inventory observations rather than asserting a
whole-pack amount. The packet deliberately does not claim upgrade persistence
for the other seven policy settings: startup-policy values are frozen when a
save is created and need separate predecessor/successor runs to make that
claim.

An upgrade begins from a source cold-load snapshot. After the successor
configuration has validated that source witness and successfully queued its
first named lab, the fixture discards only that obsolete in-memory snapshot.
It does not write saved state in `on_load`. A later cold reload captures the
completed successor state anew and still rejects changed phase, lab count,
technology, queue, effect, or inventory witnesses.

The sixteen candidate data/runtime-load calls use `-CreateOnly` with
`-ConsumerMarkers MIR5_SIF_CANDIDATE`. Their case names are exactly
`sif-science-retirement-f200-<policy>` and
`sif-science-retirement-f210-<policy>`, where `<policy>` is one of the eight
selector names. Each creates a fresh candidate map, checks the selected
runtime rows and zero-level/effect state, emits one
`[MIR5_SIF_CANDIDATE] RESULT` at `stage="init"`, and returns without a storage
or native-state write. This marker is a data/runtime-load witness only; it
cannot satisfy the full source-to-successor upgrade runner, which instead
expects `[MIR5_NATIVE_FIXTURE] RESULT` for case
`sif-science-retirement-f200` or `sif-science-retirement-f210` and the saved
published predecessor input.

The Python host control validates the packet's independent expectations,
preflight atomicity, selector boundaries, profile/archive closure, shared
staging authorities, fresh candidate zero-write branch, and fixture-control
protocol. It uses doubles only and never launches Factorio.

## Upstream-only F210 diagnostic control

`tests/profiles/sif-upstream-f210-2123.json` selects the current configured
candidate's official mods, SIF, cr-commons, cr-extras, observer, hashes and
default settings. It excludes MIR and the MIR-dependent core/selector mods.
This isolates the upstream closure without changing or patching any archive.
The historical 1.0.01 failure is retained verbatim as adverse evidence:
The raw archive identity remains cr-extras `1.0.01`; Factorio reports its
runtime version as `1.0.1`.

From the Black Glass repository checkout, the existing capture tool can use
this selection without supplying `-MIRArchive`:

```powershell
$captureRoot = Join-Path (Get-Location) 'build/tmp/sif-upstream-f210-2123-r01'
.\tools\Invoke-PrototypeCapture.ps1 `
  -ArchiveLibrary 'D:\Projects\Factorio\testmods\2.1' `
  -FactorioBin 'D:\Games\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' `
  -ProfilePath 'tests/profiles/sif-upstream-f210-2123.json' `
  -OutputRoot $captureRoot `
  -ActiveModsObserver 'mir-fixture-mir5-active-mods-observer' `
  -ExpectedPeakMemoryMiB 2048
```

Use a new output directory and the existing exclusive native lane. Retain the
actual result, loaded-mod observer, engine log and restored library controls
even if the engine rejects the upstream prototypes. A failed dump is adverse
evidence, not a passing MIR or upstream compatibility result. Match its exact
failure and inputs to the candidate observation before assigning cause; this
profile and command alone establish no native outcome or release acceptance.
