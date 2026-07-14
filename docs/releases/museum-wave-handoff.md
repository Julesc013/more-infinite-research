---
title: "MIR Fifteen-Candidate Museum Wave And 3.1.9 Handoff"
status: current
applies_to: "1.9.4 through 0.6.0 and 3.1.9"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# MIR Fifteen-Candidate Museum Wave And 3.1.9 Handoff

This is the release-manager handoff for fifteen qualified but unpublished candidates. All automated gates in the declared matrices are green, every candidate branch equals its remote branch, and all human presentation gates remain `PENDING-MAINTAINER`. No command in this document has been run unless it is explicitly described as an audit result; all tag and publication blocks are `NOT RUN`.

Released MIR 3.1.5 on `main` remains frozen at `c8bf4a742910cec9d6d3dee305c83deba1aa49eb` with archive SHA-256 `8861E25FAAC472EDE9F32FE1C051A623A59177F5E092A3B1DC0B9FF2B3D47C50`. Released MIR 2.4.0 on `legacy` remains frozen at `584b398f98d3e317fac31cba63edcb11360a5bb1` with archive SHA-256 `4BA19EA071E6359BC25C58CCD8F65CAF81B4AA675496E2F53175A996C791470C`.

The machine-readable authority for this handoff is `.mir/evidence/museum-wave-0.12-to-0.6/final-handoff.json`. Branch-local qualification summaries and seals remain the authority for target-specific runtime evidence.

## Verified Candidates

| Order | Factorio | MIR | Branch head and remote head | Binary version and SHA-256 | ZIP bytes / entries | ZIP SHA-256 | Package-content SHA-256 |
| ---: | --- | ---: | --- | --- | ---: | --- | --- |
| 1 | 1.1 | 1.9.4 | `dc6414e21585e8f565947be1c3b59ebe6bf750b8` | 1.1.110 / `B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1` | 300744 / 119 | `E350F7433F4613DE075F703435EC23FC8000ADF74FCE4F69ACEAC2DD1478BB5D` | `D17E86017F7FEFD85D6C9C839B35E4330BDEC08F42565FD6BD591E3413922DD5` |
| 2 | 1.0 | 1.8.2 | `b2855c7bbcf5adc69644820491eb8ebc17bcf362` | 1.0.0 / `99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70` | 302549 / 119 | `740F439060031B6C64925B2CBAC038912703A39F7CC2030775DEFE60C93CADD5` | `1C7EEF541E92339AD22A20E6846FCAA2B3B2FC3B5899FEC2F470F4E4996D657C` |
| 3 | 0.17 | 1.7.1 | `c59140c1808575bd26bf4156f9a6891d3cf90945` | 0.17.79 / `E699D376D100A428B95243507FDBB39C372921577C6D7593203EDF07CAA12D06` | 300744 / 117 | `E6BA58D6BAAD774712ED175E14361D130A82D7DB6DD881D5B17A3FE6E48CCCC5` | `4F0AC814FB3FDD433777971F7DE73BF8B78C239BBD928B1A2A49C950B9E355D3` |
| 4 | 0.16 | 1.6.0 | `41283b13037fd8b39c875d0d8cdc39ad1e978b23` | 0.16.51 / `ACBA4D8B766C8CB61CBB564E0D5041439DF32D93C86127DCC3887EB329630966` | 300854 / 117 | `FA1D23E5BBAF466DD609314159A4C61B588EF189630A2422ADCC70D1A16243AD` | `8DC2ADDF14F73CE1257682FDD3C97D2CD9299F1E190AD51621C300751438272E` |
| 5 | 0.15 | 1.5.0 | `c55cba5253f82bc93733522736fa303eda5acfa7` | 0.15.40 / `A1C87043244BEAE8E5903FB7D4A96E7920189C6339F00E3A2398988B9C8E7DD6` | 301024 / 117 | `3F8D78ECEC9DCCCCF2DD14279DC7E3BD696212F33C3FDD87A924B905223ACBCF` | `80AED552D7833B8B4D50B7CD150B63F42DC9EF6D8C85A317FC8B3A98552385D9` |
| 6 | 0.14 | 1.4.0 | `2e9eab88e3b6ec6ad84460c1d75d8177441182d6` | 0.14.23 / `A2B7DC0FBC1D6D68CF4D71EB71D42952FBB3B0CF35EEC6BF8B4BA16B9F79715F` | 301270 / 117 | `39EDE9BA8DA7BDD632828B0B1F055A8681FC1DAB48D7D1B9348D707BB0AF0B93` | `797CC502872D2B65ABEDF808208768173841B45AD9557408764AF700E6C3D331` |
| 7 | 0.13 | 1.3.0 | `9037ed01e04961b0b370f082ccafa5ef0b3a34f9` | 0.13.20 / `F12C0DF5A5EF0D72F50A24BD76E077DFC9CBEAB4B31EE9EF0951A4A9C086B856` | 301358 / 117 | `36EC72C5D217CE6120C5073A374B6C344BA76DF254480E9A010AA80F6B55C4CC` | `EA6F995FBC0D9266561995C19B40FE320E6840F91F92B0E7021532F56D00FB8C` |
| 8 | 0.12 | 0.12.0 | `cd06a0123292756ab569fca6d2702da72b966999` | 0.12.35 build 18124 / `AEC54627B873E4636FC2254293F01D73401CB652F373CEEE2DABEAD2B09EB774` | 2688 / 4 | `C98EBB436DD1BA1C4C0C230EB51C637EE42904000C9C7A82C7E7A33F6F5461EF` | `E50226D03EC8D3A81EB5642F10DB743A07FA59C323D2C6492F588B939634E3AA` |
| 9 | 0.11 | 0.11.0 | `5117b8ac9ae374bbce651f26e793cef9721e0da3` | 0.11.22 build 14011 / `968A6B8EDA5244F41AFB8249C7DE004C644BA4692DD38DF5BC00F26F1CE2E085` | 2514 / 4 | `C628FBFA4FC2A811869C5D33245BCBA0D37AA5EE2074ADEC7155874C2081B748` | `15428701292DBAC7037A8A82161F7EE3FF15F920B40F7CF74F59DE2EA39F88B1` |
| 10 | 0.10 | 0.10.0 | `d5346cf7ac65fd0eb0d23e50c12102d5b9eb7ca7` | 0.10.12 build 10773 / `7D8C1D11A86603C8462D1B58A1D174C83132A89E0F524BE4C0DCA97FFC1FEBB1` | 2514 / 4 | `845CBB69195ED03AF604685137D356E826B29D0570A4A4AFD6C0941E4B23C04F` | `72B988B7449F2F243353ED2E0E9007919D1B987CE5AB55B7EFD27B7A6F912F9E` |
| 11 | 0.9 | 0.9.0 | `a767c93e36e7f32c5e12f0b675ae5315d782ebbd` | 0.9.8 build 9400 / `B76D1F8058C8EB4D3F2A0B14F5DD87356B8E1068F37F85306A834AAFA611FE23` | 2505 / 4 | `9FE3117CE3415858506FBA319A2F025F170771590A23C2E160D710F4447A05F1` | `9B2CD61CF15D343345BADF0A421CCA38972947DFB055FE39D30C62B79BE772FD` |
| 12 | 0.8 | 0.8.0 | `548a880ee1fe5ed83dddd2d18844772b0e5b6a19` | 0.8.8 build 8138 / `A4226859DA746314A59D49937444F37A64828A7ABEC46AB3FC05E836C3F4C096` | 2505 / 4 | `6832B00783657F60D8AE967552CA354D1F73C988A0DFE023999AE81533267D8E` | `7A7FE34173403CF8A70D0CA95157F63B28DFB045961FAA97D9760DAE861D456B` |
| 13 | 0.7 | 0.7.0 | `d870255cc6810ad6491fa0c58f03aa9a9d2ffe0d` | 0.7.5 build 7026 / `EA52123915ECFB14658591876327490B094996ADE64D837929765147C4556FE8` | 2505 / 4 | `8495146889655FA46233A7B0416F4C67B4E2BF93E984E01F5F8234C9CA6F570F` | `69DA64132D4FEE440EFDC2531048F421E264FFD0A60A9BB8DF29E160079E4123` |
| 14 | 0.6 | 0.6.0 | `a9fb146f401187ea7b9a429be179c0c043b09858` | 0.6.4 build 5945 / `8D2F7208503B88A578FE558184C87092830554FEC5AB66BCD57CBAE2F0E5A1FB` | 2160 / 4 | `40EC4F7B07EF4219E74259DA0AA30C8095D8CEA003BDECE90E857D4379DB1C2C` | `6FF58FA7BE7184B1AA2F1FCB37F353181B4FB118CC268CE3B993ADB29E498506` |
| 15 | 2.1 | 3.1.9 | `8ab20f7e0dbf33c16ed44fac09f0dee7b3b6de5e` | 2.1.10.86940 / `DA4CA713FADBA1728904A2B47C2D73D2E07E8EB3AA2FAEED9AEE0FA6B417BAC3` | 406023 / 167 | `DE99BC1B51810EE0262120B4B7A12F5F8BE913E083B07ED0B5DA0E23C760224B` | `3DBCBBBA24F110F003E61649CC1E6A3038DD10CACC42DCC66EFEA8CBF5C19E45` |

Every row has one correctly named versioned root, zero forbidden entries, byte-deterministic builds, a matching-binary runtime gate, locale parsing/load evidence, machine balance invariants, and a verified candidate seal. Human balance and visual quality are not implied.

## Gate And Retention Matrix

| MIR | Capability / deployment | Static | Runtime | Fresh create / reload | Upgrade and retention | Seal | Publication channel |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1.9.4 | Adapted native direct effects / ZIP | Passed | 10 scenarios passed | Passed | 1.9.3 upgrade, settings and research passed | `.mir/evidence/1.9.4-candidate-seal.json` | Portal schema eligible; not uploaded |
| 1.8.2 | Adapted native direct effects / ZIP | Passed | 10 scenarios passed | Passed | 1.8.1 upgrade, settings and research passed | `.mir/evidence/1.8.2-candidate-seal.json` | Portal schema eligible; not uploaded |
| 1.7.1 | Adapted native direct effects / ZIP | Passed | 9 scenarios passed | Passed | 1.7.0 upgrade, settings and research passed | `.mir/evidence/1.7.1-candidate-seal.json` | Portal schema eligible; not uploaded |
| 1.6.0 | Adapted native direct effects / ZIP | Passed | 8 scenarios passed | Passed | No legitimate prior; fresh retention passed | `.mir/evidence/1.6.0-candidate-seal.json` | Portal schema eligible; not uploaded |
| 1.5.0 | Adapted native direct effects / ZIP | Passed | 4 scenarios passed | Passed | No legitimate prior; fresh retention passed | `.mir/evidence/1.5.0-candidate-seal.json` | Portal schema eligible; not uploaded |
| 1.4.0 | Finite reconstruction / ZIP | Passed | 2 scenarios passed | Passed | No legitimate prior; fresh retention passed | `.mir/evidence/1.4.0-candidate-seal.json` | Portal schema eligible; not uploaded |
| 1.3.0 | Finite reconstruction / ZIP | Passed | 2 scenarios passed | Passed | No legitimate prior; fresh retention passed | `.mir/evidence/1.3.0-candidate-seal.json` | Portal schema eligible; not uploaded |
| 0.12.0 | Museum finite ladder / ZIP-native | Passed | Exact ZIP passed | Fresh create and bounded server reload passed | First release; upgrade N/A with evidence; `config.lua` retention passed | `.mir/evidence/0.12.0-candidate-seal.json` | GitHub/archive only |
| 0.11.0 | Museum finite ladder / ZIP-native | Passed | Two bounded starts passed | Save proof unavailable in target CLI | First release; upgrade N/A with evidence; loaded config passed | `.mir/evidence/0.11.0-candidate-seal.json` | GitHub/archive only |
| 0.10.0 | Museum finite ladder / ZIP-native | Passed | Two bounded starts passed | Save proof unavailable in target CLI | First release; config isolation restored | `.mir/evidence/0.10.0-candidate-seal.json` | GitHub/archive only |
| 0.9.0 | Museum finite ladder / ZIP-native | Passed | Two regenerated cache proofs passed | Save proof unavailable in target CLI | First release; config isolation restored | `.mir/evidence/0.9.0-candidate-seal.json` | GitHub/archive only |
| 0.8.0 | Museum finite ladder / extract-required | Passed | Two extracted regenerated cache proofs passed | Save proof unavailable in target CLI | First release; config isolation restored | `.mir/evidence/0.8.0-candidate-seal.json` | GitHub/archive only |
| 0.7.0 | Museum finite ladder / extract-required | Passed | Two extracted regenerated cache proofs passed | Save proof unavailable in target CLI | First release; config isolation restored | `.mir/evidence/0.7.0-candidate-seal.json` | GitHub/archive only |
| 0.6.0 | Minimal museum finite ladder / extract-required | Passed | Two extracted regenerated cache proofs passed | Save proof unavailable in target CLI | First release; config isolation restored | `.mir/evidence/0.6.0-candidate-seal.json` | GitHub/archive only |
| 3.1.9 | Canonical modern compiler / ZIP | Passed | 102 registered scenarios and 11 mandatory groups passed | Base and Space Age exact ZIP passed | 3.1.5, 3.1.2, and 3.0.5 upgrades; exact level/current research/0.42 progress passed | `.mir/evidence/candidate-seals/mir-3.1.9-factorio-2.1.json` | Portal schema eligible; not uploaded |

The portal classifications come from `.mir/evidence/museum-wave-0.12-to-0.6/publication-channel-audit.json`. The public API accepted version filters from 0.13 through 2.1 and rejected 0.12 through 0.6. Schema eligibility is not an upload claim; exact upload and presentation remain pending.

## Museum Capability Matrix

| Factorio / MIR | Proven effects | Science packs | Technology and finite bounds | Deployment / locale / config | Explicit omissions | Binary proof |
| --- | --- | --- | --- | --- | --- | --- |
| 0.12 / 0.12.0 | Inserter stack, turret attack, gun speed, ammo damage, quick bars, logistic trash slots | `science-pack-1`, `science-pack-2`, `science-pack-3`, `alien-science-pack` | Numbered finite technologies; 5 levels for four combat/inserter families and 3 levels for toolbelt/trash slots | ZIP-native; CFG sections; loaded `config.lua` | Infinite fields, formula counts, recipe/mining productivity, modern settings, scripts | Fresh create and bounded server reload on 0.12.35 |
| 0.11 / 0.11.0 | Inserter stack, turret attack, gun speed, ammo damage, quick bars | Same four packs | Numbered finite technologies; 5 levels for four families and 3 toolbelt levels | ZIP-native; CFG sections; loaded `config.lua` | Same, plus no save automation because target CLI lacks it | Two bounded startups on final 0.11.22 |
| 0.10 / 0.10.0 | Inserter stack, turret attack, gun speed, ammo damage, quick bars | Same four packs | 23 numbered finite technologies across five families | ZIP-native; CFG sections; loaded `config.lua` | Infinite fields, productivity, modern settings, dynamic discovery, scripts | Two bounded startups and config restoration on 0.10.12 |
| 0.9 / 0.9.0 | Inserter stack, turret attack, gun speed, ammo damage, quick bars | Same four packs | 23 numbered finite technologies across five families | ZIP-native; CFG sections; loaded `config.lua` | Same | Two regenerated cache proofs and config restoration on 0.9.8 |
| 0.8 / 0.8.0 | Inserter stack, turret attack, gun speed, ammo damage, quick bars | Same four packs | 23 numbered finite technologies across five families | Extract-required; CFG sections; loaded `config.lua` | Same | Two extracted regenerated cache proofs on 0.8.8 |
| 0.7 / 0.7.0 | Inserter stack, turret attack, gun speed, ammo damage, quick bars | Same four packs | 23 numbered finite technologies across five families | Extract-required; CFG sections; loaded `config.lua` | Same | Two extracted regenerated cache proofs on 0.7.5 |
| 0.6 / 0.6.0 | Inserter stack, rocket gun speed, rocket ammo damage | Same four packs | 15 numbered finite technologies; 5 levels in each of three families | Extract-required; CFG sections; loaded `config.lua` | Turret attack, toolbelt, infinite fields, productivity, modern settings, dynamic discovery, scripts | Two extracted regenerated cache proofs on 0.6.4 |

Every generated museum technology has a stable stream-manifest row. The shared museum compiler passed seven deterministic builds and 25 negative cases covering duplicate IDs and locale keys, graph defects, unsupported effects/science/fields, modern leakage, invalid balance, archive roots, locale syntax, icons, target versions, and extraction manifests.

## Portable Fix Ledger

| Class / origin | Root cause and fix | Regression | Candidate effect | 3.1.9 disposition | 3.2.0 disposition |
| --- | --- | --- | --- | --- | --- |
| Settings / tmp/2.0 | Recognized native infinite owners did not honor stable stream settings; add native-owner binding | Native owner scenarios and compiler contracts | Released/sealed historical bytes not invalidated | Implemented | Retain contract during future refactor |
| Compiler / tmp/2.0 | Owner changes needed immutable input/output fingerprints and one transaction | Transaction and duplicate-binding cases | None | Implemented | Retain invariant |
| Balance / tmp/2.0 | Defaults and unknown formulas needed explicit preservation/rejection | Balance manifest and formula scenarios | None | Rebound to Factorio 2.1.10 | Playtest/tune later without weakening safety |
| Evidence / tmp/2.0 | Broad gates lacked change-impact and exact-input reuse | Assurance self-test | None | Implemented | Retain |
| Packaging / tmp/2.0 | Runtime could validate a rebuild instead of the candidate | Exact candidate and seal identity checks | None | Implemented | Retain |
| Graph / tmp/1.1 | Recursive traversal risked deep-graph failure | 4096-node scenario | None | Already present in 3.1.5 | Retain |
| Generator / museum wave | Old engines require static finite output and capability rejection | Seven builds plus 25 negatives | No higher candidate invalidated | Development tooling only | Keep separate from modern runtime |
| Harness / museum wave | Package discovery and CLI flags differ by target | Matching-binary runtime and seal checks | None | Development tooling only | Retain target capabilities |
| Harness / 3.1.9 | Selected Space Age runs did not enforce native-owner post-load assertions | Two selected integrity scenarios | Only unsealed prequalification bytes changed | Implemented | Retain |
| Settings / 3.1.9 | Base and growth fields could activate independently | Cost-base, growth, combined, and contract cases | Only unsealed prequalification bytes changed | Implemented atomically | Retain |
| Upgrade / 3.1.9 | Factorio rescales research progress when unit cost changes | Exact 3.1.5 upgrade with level/current research/0.42 progress | Only unsealed prequalification bytes changed | Implemented with floored unit counts | Retain |

The complete branch-by-branch disposition ledger is on `tmp/3.1.9-synthesis` at `.mir/evidence/3.1.9/portable-fix-ledger.json`. The fixed-point sweep reports zero new fixes, stale seals, unclassified files, or candidate branch mismatches.

## Target-Specific Ledger

| Target | Capability / implementation | Proof | Why target-local |
| --- | --- | --- | --- |
| 1.1 | Omit recipe-productivity streams and settings, including LDS, plastic, processing units, and rocket fuel | Capability/static/runtime matrix | Target lacks the modern technology effect |
| 1.0 | Preserve reduced direct-effect surface and target runtime adapter | 10 scenarios and upgrade | API/runtime generation differs from modern line |
| 0.17 | Old science and `global` runtime boundary | 9 scenarios and upgrade | Target API and science are not modern defaults |
| 0.16 | Old-science native-infinite mapping | 8 scenarios | Target-specific science progression |
| 0.15 | Minimal native-infinite floor | 4 scenarios | Earliest proven native-infinite surface |
| 0.14 / 0.13 | Finite reconstruction | 2 scenarios each | Native infinite parity is not proven |
| 0.12 | Six finite families and ZIP-native deployment | Exact binary create/reload | Old technology/config/locale schema |
| 0.11 / 0.10 | Five finite families and bounded startup evidence | Exact final binaries | Target CLI cannot provide modern save proof |
| 0.9 | Cache-regeneration proof | Two cache markers | Target CLI/log behavior |
| 0.8 / 0.7 | Extract-required deployment | Two extracted cache proofs each | ZIP discovery is unsupported |
| 0.6 | Three-family minimal finite floor | Two extracted cache proofs | Only three effects are proven |

No lower-target runtime source, metadata, science names, effect names, package format, locale syntax, `config.lua`, or finite technology entered the 3.1.9 release ZIP. The modern ZIP contains no museum distribution, tooling, evidence, fixture, or old-target source.

## Supersession Ledger

| MIR | Superseded source / ZIP SHA-256 | Reason | Final branch head / ZIP SHA-256 | Seal disposition |
| ---: | --- | --- | --- | --- |
| 1.9.4 | `30ef8c7cab3c049aa0bb5efa0d74dd12e9c1ec40` / `9184524A2E37115F6D30830191054F70AE556142306E226CDAE4308DC7285A35` | Portable correction wave | `dc6414e21585e8f565947be1c3b59ebe6bf750b8` / `E350F7433F4613DE075F703435EC23FC8000ADF74FCE4F69ACEAC2DD1478BB5D` | Old identity retained as superseded evidence; final seal is `.mir/evidence/1.9.4-candidate-seal.json` |
| 1.8.2 | `0b06b9b0420e1fec38959adbc5cdef91e88a9ea0` / `1D474CF4CEEB4F1D8F9CFA1494BE98D2E903C5A511871AE01FBB83682DF1EDF6` | Portable correction wave | `b2855c7bbcf5adc69644820491eb8ebc17bcf362` / `740F439060031B6C64925B2CBAC038912703A39F7CC2030775DEFE60C93CADD5` | Final seal is `.mir/evidence/1.8.2-candidate-seal.json` |
| 1.7.1 | `efb5d0af347bd8f0ad8966425dfcc7dea75217f2` / `CC112180F3D099C1C75AD230061A4B9123AE2F30F8585838D3053BD309771BFA` | Portable correction wave | `c59140c1808575bd26bf4156f9a6891d3cf90945` / `E6BA58D6BAAD774712ED175E14361D130A82D7DB6DD881D5B17A3FE6E48CCCC5` | Final seal is `.mir/evidence/1.7.1-candidate-seal.json` |
| 1.6.0 | `2dfb1a716441e3f73c33b776f374938702a622ec` / `6EE5FF574C4681D5E33B971EA2CD646100B8E862544C4BCB4581BDAEEB246BAB` | Portable correction wave | `41283b13037fd8b39c875d0d8cdc39ad1e978b23` / `FA1D23E5BBAF466DD609314159A4C61B588EF189630A2422ADCC70D1A16243AD` | Final seal is `.mir/evidence/1.6.0-candidate-seal.json` |
| 1.5.0 | `d4167875b97c45b460131ef3436e16ee21774c14` / `2EB2E9650FD77485E064869F8CDC578801A97EF0FF237ABFB3C46224604A5817` | Portable correction wave | `c55cba5253f82bc93733522736fa303eda5acfa7` / `3F8D78ECEC9DCCCCF2DD14279DC7E3BD696212F33C3FDD87A924B905223ACBCF` | Final seal is `.mir/evidence/1.5.0-candidate-seal.json` |
| 1.4.0 | `fa3b532fa158ed506f474f5ad3796e032332f012` / `F6E90F291C838A8DAB80AE1E340D897ADFC14E8A7657B2D01D93C18B476DCBD6` | Portable correction wave | `2e9eab88e3b6ec6ad84460c1d75d8177441182d6` / `39EDE9BA8DA7BDD632828B0B1F055A8681FC1DAB48D7D1B9348D707BB0AF0B93` | Final seal is `.mir/evidence/1.4.0-candidate-seal.json` |
| 1.3.0 | `095264d6b422b8d70925d39b8cce017a8ab8e003` / `3061783FEF696FFA48D9E63EE6473A647F1C56CBC3FC6C396AB922005C0C80AF` | Portable correction wave | `9037ed01e04961b0b370f082ccafa5ef0b3a34f9` / `36EC72C5D217CE6120C5073A374B6C344BA76DF254480E9A010AA80F6B55C4CC` | Final seal is `.mir/evidence/1.3.0-candidate-seal.json` |

The museum planning snapshots were not candidates and therefore are not recorded as superseded release bytes. Intermediate 3.1.9 package refreshes were unsealed prequalification builds; only the final archive is a sealed candidate.

## Branch And Origin Audit

| Ref | Local | Origin | Ahead / behind | Worktree | Push status |
| --- | --- | --- | --- | --- | --- |
| `main` | `c8bf4a742910cec9d6d3dee305c83deba1aa49eb` | same | 0 / 0 | Pre-existing untracked released 2.4.0 ZIP; untouched | Frozen/equal |
| `dev` | `8ab20f7e0dbf33c16ed44fac09f0dee7b3b6de5e` | same | 0 / 0 | Not checked out | Pushed by ordinary fast-forward |
| `legacy` | `584b398f98d3e317fac31cba63edcb11360a5bb1` | same | 0 / 0 | Clean | Frozen/equal |
| `tmp/2.0` | `21b100777cc12598971a793f5b098ee208927b0c` | same | 0 / 0 | Not checked out | Equal; released 2.4.0 anchor is `legacy` |
| `tmp/1.1` | `dc6414e21585e8f565947be1c3b59ebe6bf750b8` | same | 0 / 0 | Clean | Pushed |
| `tmp/1.0` | `b2855c7bbcf5adc69644820491eb8ebc17bcf362` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.18` | `e75823366f49dc4afede6d43a03f982a9a072043` | same | 0 / 0 | Not checked out | Existing published bridge/equal |
| `tmp/0.17` | `c59140c1808575bd26bf4156f9a6891d3cf90945` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.16` | `41283b13037fd8b39c875d0d8cdc39ad1e978b23` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.15` | `c55cba5253f82bc93733522736fa303eda5acfa7` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.14` | `2e9eab88e3b6ec6ad84460c1d75d8177441182d6` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.13` | `9037ed01e04961b0b370f082ccafa5ef0b3a34f9` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.12` | `cd06a0123292756ab569fca6d2702da72b966999` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.11` | `5117b8ac9ae374bbce651f26e793cef9721e0da3` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.10` | `d5346cf7ac65fd0eb0d23e50c12102d5b9eb7ca7` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.9` | `a767c93e36e7f32c5e12f0b675ae5315d782ebbd` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.8` | `548a880ee1fe5ed83dddd2d18844772b0e5b6a19` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.7` | `d870255cc6810ad6491fa0c58f03aa9a9d2ffe0d` | same | 0 / 0 | Clean | Pushed |
| `tmp/0.6` | `a9fb146f401187ea7b9a429be179c0c043b09858` | same | 0 / 0 | Clean | Pushed |
| `tmp/backport-wave-2.4.0` | `e90eea0841ea43a626570eeb4533285db4639b58` | same | 0 / 0 | Clean | Pushed |
| `tmp/3.1.9-synthesis` | `8ab20f7e0dbf33c16ed44fac09f0dee7b3b6de5e` | same | 0 / 0 | Clean | Pushed |
| `tmp/museum-wave-and-3.1.9-handoff` | `HEAD` | `origin/tmp/museum-wave-and-3.1.9-handoff` after the handoff push | 0 / 0 after push | Clean after commit | Push required for this handoff commit |

The aggregate row uses `HEAD` because a commit cannot contain its own object ID. The release-manager must resolve and compare it after fetching; the final campaign response records the resulting full SHA.

### Campaign Safety Refs

| Safety ref | Local and origin SHA | Status |
| --- | --- | --- |
| `safety/pre-2.4.0-wave/1.1-16879c8` | `16879c88aeb0f18f043e335ba606be46f65d2535` | Equal |
| `safety/pre-2.4.0-wave/1.0-fdc9e37` | `fdc9e37ebae444f59c9c78fe751fbcd69a6bd9c9` | Equal |
| `safety/pre-2.4.0-wave/0.17-bb12acb` | `bb12acb29cbef4cd141f157b6ed5e6f4c5e8f494` | Equal |
| `safety/pre-2.4.0-wave/0.16-1429b02` | `1429b02f09d0a693389124dc7b9d1b29033a960b` | Equal |
| `safety/pre-2.4.0-wave/0.15-b3647fa` | `b3647fa491bf8b868bfe9b46c82db6da78256cba` | Equal |
| `safety/pre-2.4.0-wave/0.14-42aa2ea` | `42aa2eacba7095c21a8cf1050510b7dbacb52298` | Equal |
| `safety/pre-2.4.0-wave/0.13-4269281` | `42692819544c24cc2f88a66f4dfe35d0298de20f` | Equal |
| `safety/pre-museum-wave/0.12-acfba01` | `acfba01036a7955128750b2ae67edbfef3dcf13a` | Equal |
| `safety/pre-museum-wave/0.11-03ac230` | `03ac230c3d20f229dadfaa6e0ccf71135bb0bc10` | Equal |
| `safety/pre-museum-wave/0.10-3c39b42` | `3c39b428f82c6a422402f0eadf379e7a9ec806d9` | Equal |
| `safety/pre-museum-wave/0.9-d86dfd6` | `d86dfd656f4e83cf34e7100e3657688123aef5e0` | Equal |
| `safety/pre-museum-wave/0.8-41c2c4f` | `41c2c4f842548ddbc7c3513795acd3e12bef4dc3` | Equal |
| `safety/pre-museum-wave/0.7-7e964b4` | `7e964b4705e15ff2365a06a9e00901fae751c0c7` | Equal |
| `safety/pre-museum-wave/0.6-20a94c4` | `20a94c4dc5abffd7b36d0590f253162afd428645` | Equal |
| `safety/pre-3.1.9/dev-c8bf4a7` | `c8bf4a742910cec9d6d3dee305c83deba1aa49eb` | Equal |

Older safety refs `safety/legacy-before-1.9.2-backport`, `safety/legacy-before-1.9.5-backport`, `safety/legacy-before-2.3.0-promotion`, and `safety/tmp-2.0-before-dev-sync` remain local-only historical refs. `safety/tmp-2.0-before-2.4.0-regeneration` and `safety/tmp-2.0-before-native-owner-settings-repair` remain equal to origin. None was moved or deleted.

## Blocked Inputs

There are no unresolved automated external inputs. Manual visual, presentation, and balance decisions are gates, not blocked automated inputs.

## Manual Gates

The following remain `PENDING-MAINTAINER` for every applicable candidate:

- Visual locale fit and truncation.
- Icon presentation.
- Technology-tree presentation.
- Human balance judgment.
- Save and settings UI review.
- GitHub release presentation.
- Mod Portal eligibility/presentation confirmation for 0.13 and newer.

Automated locale parsing, prototype loading, and numeric balance invariants do not mark these human gates passed.

## No-Release Audit

- Tag count before and after: 31.
- Sorted tag-name SHA-256: `4F2F8F97E7674AF03DADC8E57147F999C9A48F1E11E6FCAE5B302543B01AEA28`.
- Sorted tag-name/object SHA-256: `753A89FE4B8BC511D8BAA71A51CCCA650635FB8A053B96D1BCCAD5B9426E5761`.
- Tracked initial and final tag snapshots are byte-identical at SHA-256 `608B8AE5B82D1D31841E047C382249B46D0C5508BD5ECE92389BE86AB80B2FFA`.
- No tag was created, moved, replaced, or deleted.
- No GitHub release was created or modified.
- No Mod Portal upload was made.
- No public artifact was published.
- No force-push was used.
- `main`, `legacy`, released 3.1.5 bytes, and released 2.4.0 bytes are unchanged.
- MIR 3.2.0 work was not begun.

## Future Commands — NOT RUN

### Verify Candidate Seals

Run each command from the named candidate branch worktree:

```powershell
# NOT RUN — 1.9.4 through 1.3.0, one command in each corresponding worktree
.\scripts\Invoke-MIRBackportQualification.ps1 -Action check-seal

# NOT RUN — museum candidates, one command in each corresponding worktree
.\scripts\Test-MIRMuseumSeal.ps1 -FactorioVersion 0.12
.\scripts\Test-MIRMuseumSeal.ps1 -FactorioVersion 0.11
.\scripts\Test-MIRMuseumSeal.ps1 -FactorioVersion 0.10
.\scripts\Test-MIRMuseumSeal.ps1 -FactorioVersion 0.9
.\scripts\Test-MIRMuseumSeal.ps1 -FactorioVersion 0.8
.\scripts\Test-MIRMuseumSeal.ps1 -FactorioVersion 0.7
.\scripts\Test-MIRMuseumSeal.ps1 -FactorioVersion 0.6

# NOT RUN — 3.1.9 synthesis worktree
.\scripts\mir.ps1 assurance check-seal --seal .mir/evidence/candidate-seals/mir-3.1.9-factorio-2.1.json
```

### Verify Branches And Remotes

```powershell
# NOT RUN
git fetch origin --prune
$branches = @('tmp/1.1','tmp/1.0','tmp/0.17','tmp/0.16','tmp/0.15','tmp/0.14','tmp/0.13','tmp/0.12','tmp/0.11','tmp/0.10','tmp/0.9','tmp/0.8','tmp/0.7','tmp/0.6','tmp/3.1.9-synthesis','dev','main','legacy','tmp/museum-wave-and-3.1.9-handoff')
foreach ($branch in $branches) {
  $local = git rev-parse $branch
  $remote = git rev-parse "origin/$branch"
  if ($local -ne $remote) { throw "$branch differs: $local != $remote" }
}
```

### Create Annotated Tags And Push Them

Use signed tags instead by replacing `-a` with `-s` when signing is configured. These commands are intentionally not run:

```powershell
# NOT RUN
git tag -a 1.9.4 dc6414e21585e8f565947be1c3b59ebe6bf750b8 -m "MIR 1.9.4 for Factorio 1.1"
git tag -a 1.8.2 b2855c7bbcf5adc69644820491eb8ebc17bcf362 -m "MIR 1.8.2 for Factorio 1.0"
git tag -a 1.7.1 c59140c1808575bd26bf4156f9a6891d3cf90945 -m "MIR 1.7.1 for Factorio 0.17"
git tag -a 1.6.0 41283b13037fd8b39c875d0d8cdc39ad1e978b23 -m "MIR 1.6.0 for Factorio 0.16"
git tag -a 1.5.0 c55cba5253f82bc93733522736fa303eda5acfa7 -m "MIR 1.5.0 for Factorio 0.15"
git tag -a 1.4.0 2e9eab88e3b6ec6ad84460c1d75d8177441182d6 -m "MIR 1.4.0 for Factorio 0.14"
git tag -a 1.3.0 9037ed01e04961b0b370f082ccafa5ef0b3a34f9 -m "MIR 1.3.0 for Factorio 0.13"
git tag -a 0.12.0 cd06a0123292756ab569fca6d2702da72b966999 -m "MIR 0.12.0 for Factorio 0.12"
git tag -a 0.11.0 5117b8ac9ae374bbce651f26e793cef9721e0da3 -m "MIR 0.11.0 for Factorio 0.11"
git tag -a 0.10.0 d5346cf7ac65fd0eb0d23e50c12102d5b9eb7ca7 -m "MIR 0.10.0 for Factorio 0.10"
git tag -a 0.9.0 a767c93e36e7f32c5e12f0b675ae5315d782ebbd -m "MIR 0.9.0 for Factorio 0.9"
git tag -a 0.8.0 548a880ee1fe5ed83dddd2d18844772b0e5b6a19 -m "MIR 0.8.0 for Factorio 0.8"
git tag -a 0.7.0 d870255cc6810ad6491fa0c58f03aa9a9d2ffe0d -m "MIR 0.7.0 for Factorio 0.7"
git tag -a 0.6.0 a9fb146f401187ea7b9a429be179c0c043b09858 -m "MIR 0.6.0 for Factorio 0.6"
git tag -a 3.1.9 8ab20f7e0dbf33c16ed44fac09f0dee7b3b6de5e -m "MIR 3.1.9 for Factorio 2.1"

git push origin 1.9.4 1.8.2 1.7.1 1.6.0 1.5.0 1.4.0 1.3.0 0.12.0 0.11.0 0.10.0 0.9.0 0.8.0 0.7.0 0.6.0 3.1.9
```

### Create GitHub Releases

Run each command from its candidate worktree after its annotated or signed tag exists:

```powershell
# NOT RUN
gh release create 1.9.4 dist/more-infinite-research_1.9.4.zip --verify-tag --title "MIR 1.9.4 for Factorio 1.1" --notes-file docs/releases/release-notes-1.9.4.md
gh release create 1.8.2 dist/more-infinite-research_1.8.2.zip --verify-tag --title "MIR 1.8.2 for Factorio 1.0" --notes-file docs/releases/release-notes-1.8.2.md
gh release create 1.7.1 dist/more-infinite-research_1.7.1.zip --verify-tag --title "MIR 1.7.1 for Factorio 0.17" --notes-file docs/releases/release-notes-1.7.1.md
gh release create 1.6.0 dist/more-infinite-research_1.6.0.zip --verify-tag --title "MIR 1.6.0 for Factorio 0.16" --notes-file docs/releases/release-notes-1.6.0.md
gh release create 1.5.0 dist/more-infinite-research_1.5.0.zip --verify-tag --title "MIR 1.5.0 for Factorio 0.15" --notes-file docs/releases/release-notes-1.5.0.md
gh release create 1.4.0 dist/more-infinite-research_1.4.0.zip --verify-tag --title "MIR 1.4.0 for Factorio 0.14" --notes-file docs/releases/release-notes-1.4.0.md
gh release create 1.3.0 dist/more-infinite-research_1.3.0.zip --verify-tag --title "MIR 1.3.0 for Factorio 0.13" --notes-file docs/releases/release-notes-1.3.0.md
gh release create 0.12.0 dist/more-infinite-research_0.12.0.zip --verify-tag --title "MIR 0.12.0 for Factorio 0.12" --notes-file docs/releases/0.12.0-release-packet.md
gh release create 0.11.0 dist/more-infinite-research_0.11.0.zip --verify-tag --title "MIR 0.11.0 for Factorio 0.11" --notes-file docs/releases/0.11.0-release-packet.md
gh release create 0.10.0 dist/more-infinite-research_0.10.0.zip --verify-tag --title "MIR 0.10.0 for Factorio 0.10" --notes-file docs/releases/0.10.0-release-packet.md
gh release create 0.9.0 dist/more-infinite-research_0.9.0.zip --verify-tag --title "MIR 0.9.0 for Factorio 0.9" --notes-file docs/releases/0.9.0-release-packet.md
gh release create 0.8.0 dist/more-infinite-research_0.8.0.zip --verify-tag --title "MIR 0.8.0 for Factorio 0.8" --notes-file docs/releases/0.8.0-release-packet.md
gh release create 0.7.0 dist/more-infinite-research_0.7.0.zip --verify-tag --title "MIR 0.7.0 for Factorio 0.7" --notes-file docs/releases/0.7.0-release-packet.md
gh release create 0.6.0 dist/more-infinite-research_0.6.0.zip --verify-tag --title "MIR 0.6.0 for Factorio 0.6" --notes-file docs/releases/0.6.0-release-packet.md
gh release create 3.1.9 dist/more-infinite-research_3.1.9.zip --verify-tag --title "MIR 3.1.9 for Factorio 2.1" --notes-file docs/releases/notes/release-notes-3.1.9.md
```

### Publish Portal-Eligible Archives

Do not call this helper for 0.12.0 through 0.6.0. It requires an API key with Mod Portal upload scope and is intentionally not run:

```powershell
# NOT RUN
function Publish-MIRPortalArchive([string]$Archive) {
  $headers = @{ Authorization = "Bearer $env:FACTORIO_MOD_PORTAL_API_KEY" }
  $init = Invoke-RestMethod -Method Post -Uri 'https://mods.factorio.com/api/v2/mods/releases/init_upload' -Headers $headers -Form @{ mod = 'more-infinite-research' }
  Invoke-RestMethod -Method Post -Uri $init.upload_url -Form @{ file = Get-Item -LiteralPath $Archive }
}

Publish-MIRPortalArchive 'dist/more-infinite-research_1.9.4.zip'
Publish-MIRPortalArchive 'dist/more-infinite-research_1.8.2.zip'
Publish-MIRPortalArchive 'dist/more-infinite-research_1.7.1.zip'
Publish-MIRPortalArchive 'dist/more-infinite-research_1.6.0.zip'
Publish-MIRPortalArchive 'dist/more-infinite-research_1.5.0.zip'
Publish-MIRPortalArchive 'dist/more-infinite-research_1.4.0.zip'
Publish-MIRPortalArchive 'dist/more-infinite-research_1.3.0.zip'
Publish-MIRPortalArchive 'dist/more-infinite-research_3.1.9.zip'
```

### Verify Public Assets And Record Publication

```powershell
# NOT RUN — after each GitHub asset exists
$expected = @{
  '1.9.4'='E350F7433F4613DE075F703435EC23FC8000ADF74FCE4F69ACEAC2DD1478BB5D'; '1.8.2'='740F439060031B6C64925B2CBAC038912703A39F7CC2030775DEFE60C93CADD5'; '1.7.1'='E6BA58D6BAAD774712ED175E14361D130A82D7DB6DD881D5B17A3FE6E48CCCC5'; '1.6.0'='FA1D23E5BBAF466DD609314159A4C61B588EF189630A2422ADCC70D1A16243AD'; '1.5.0'='3F8D78ECEC9DCCCCF2DD14279DC7E3BD696212F33C3FDD87A924B905223ACBCF'; '1.4.0'='39EDE9BA8DA7BDD632828B0B1F055A8681FC1DAB48D7D1B9348D707BB0AF0B93'; '1.3.0'='36EC72C5D217CE6120C5073A374B6C344BA76DF254480E9A010AA80F6B55C4CC'; '0.12.0'='C98EBB436DD1BA1C4C0C230EB51C637EE42904000C9C7A82C7E7A33F6F5461EF'; '0.11.0'='C628FBFA4FC2A811869C5D33245BCBA0D37AA5EE2074ADEC7155874C2081B748'; '0.10.0'='845CBB69195ED03AF604685137D356E826B29D0570A4A4AFD6C0941E4B23C04F'; '0.9.0'='9FE3117CE3415858506FBA319A2F025F170771590A23C2E160D710F4447A05F1'; '0.8.0'='6832B00783657F60D8AE967552CA354D1F73C988A0DFE023999AE81533267D8E'; '0.7.0'='8495146889655FA46233A7B0416F4C67B4E2BF93E984E01F5F8234C9CA6F570F'; '0.6.0'='40EC4F7B07EF4219E74259DA0AA30C8095D8CEA003BDECE90E857D4379DB1C2C'; '3.1.9'='DE99BC1B51810EE0262120B4B7A12F5F8BE913E083B07ED0B5DA0E23C760224B'
}
foreach ($version in $expected.Keys) {
  $name = "more-infinite-research_$version.zip"
  gh release download $version --pattern $name --dir "public-asset-check/$version" --clobber
  $actual = (Get-FileHash -Algorithm SHA256 "public-asset-check/$version/$name").Hash
  if ($actual -ne $expected[$version]) { throw "$version public asset mismatch" }
}

# NOT RUN — after hashes and public presentation are accepted
# Update branch-local release status/evidence without rebuilding any ZIP, commit the docs/evidence-only change, and push the branch normally.
git add .mir docs
git commit -m "docs(release): record verified publication"
git push origin HEAD
```

Release in the order shown in the verified-candidate table. Promote the sealed bytes exactly; do not rebuild them during publication.
