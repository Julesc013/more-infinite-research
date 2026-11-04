---
title: "MIR 5.0.3 beta release notes"
status: draft
applies_to: "MIR 5.0.3 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-503-release-note-draft
---

- **MIR 5.0.3 beta:** cumulative compatibility and saved-research corrections, including the completed 5.0.2 work. GitHub prerelease; stable qualification remains unfinished.
- **Glass compatibility:** keep Krastorio 2: Spaced Out research loading when Crushing Industry replaces its glass recipe. Preserve earned bonuses on both glass recipes, partial work and the research queue through the checked upgrade.
- **Research ownership and settings:** apply cost and time settings to compatible native productivity research; retain separate MIR research when native progression cannot safely represent those settings. Preserve recipe-specific earned bonuses and unfinished work when ownership changes, including destination-force history during force merges.
- **Space Is Fake:** preserve affected paid manufacturing research and inherited-time settings. Keep the historical science requirements on private recovery research so provider removal does not discard queued work.
- **Other corrections:** retain Secretas's finite worker-robot storage research and continue from level 9 with inherited science and effects; improve Russian research and setting wording, including percentage explanations.
- **Configurations checked:** selected Base upgrades from published 4.7.3 and 5.0.2, and Space Is Fake 1.0.60 saved-research transitions on Factorio 2.0.77/2.1.23. The reduced Krastorio 2: Spaced Out 2.0.19 + Crushing Industry 0.6.9/FDSL 0.5.5 case includes paid-state preservation, real glass research and two cold reloads. Some cases seed earned state or accelerate research; they do not establish ordinary research costs, physical production, every mod combination or the reporter's complete installation.
- **Upgrade limits:** retain the documented limits for externally disabled research. These checks do not qualify arbitrary scripted force overrides. Unknown prior ownership is refused before MIR changes its saved research state; keep your original save.
- **Beta limits:** some external weapon-speed research can overlap dedicated MIR research; this remains under investigation. Full Library input, exports, saved-view/client lifecycle and Discovery Tree's None/reset visual behavior remain unfinished. Historical coverage and whole-product factory performance/retained-memory testing remain open; no general performance improvement is claimed.
- **Before upgrading:** back up your save and test a copy with the same mods and settings. Follow the [upgrade guide](https://github.com/Julesc013/more-infinite-research/blob/v5.0.3/docs/support.md#first-upgrade).
- **Downloads:** choose the archive labelled for your Factorio version; each label states its minimum version. Factorio 0.18.47 is experimental, best effort and GitHub-only; its in-game load/crash check remains unverified.
- **Early downloads (Factorio 0.6–0.12):** finite Base research with fixed defaults only; no MIR runtime effects, mod settings, Research Library, runtime API or save migrations. These builds remain best effort and untested in-game. Unzip the Factorio 0.6–0.8 downloads into the mods folder.
- **Bug reports:** include Factorio and MIR versions, the complete mod list, settings, the current log and a reproducible save where possible. See [support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.3/SUPPORT.md).
