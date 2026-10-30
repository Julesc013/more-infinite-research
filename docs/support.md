---
title: "Support and upgrade guide"
status: current
applies_to: "MIR players and upgrades"
audience: player
doc_type: guide
owner: mir-maintainers
last_reviewed: 2026-10-31
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-support-guide
---

# Support and upgrade guide

- Use the release notes for the current prerelease status. This guide explains which package to choose, how to upgrade safely and what to include in a support request. Technical qualification details and unfinished work are recorded in [progress](progress.md).

## Candidate editions

- Choose the package for the Factorio version you actually run. Do not choose another package because its number is larger.

| Factorio family | Minimum version | Player-facing scope |
| --- | --- | --- |
| 2.1 | 2.1.23 | Research, Library and supported Space Age content when its official mods are enabled. |
| 2.0 | 2.0.77 | Research and Library. |
| 1.1 | 1.1.110 | Historical direct-effect subset; no Library or recipe productivity. |
| 1.0 | 1.0.0 | Historical direct-effect subset; no Library or recipe productivity. |
| 0.17 | 0.17.79 | Historical direct-effect subset. |
| 0.16 | 0.16.51 | Historical direct-effect subset; no built-in research queue. |
| 0.15 | 0.15.40 | Historical direct-effect subset; no built-in research queue. |
| 0.14 | 0.14.23 | Historical direct-effect subset. |
| 0.13 | 0.13.20 | Historical direct-effect subset. |

- Recipe productivity and the Research Library are available only on Factorio 2.0 and 2.1. Space Age research needs the relevant official content, science and labs. Historical editions do not gain Library, recipe-productivity or expansion features.

- Factorio 0.13 and 0.14 cannot show later numeric infinite-research levels. Factorio 0.13 through 0.16 have no built-in research queue.

- The first MIR 5 beta is GitHub-only; it is not the stable release. Its normal edition packages remain subject to the stated release and support limits.

## Additional best-effort historical builds

| Factorio family | Availability | Important limit |
| --- | --- | --- |
| 0.18.47 | GitHub-only experimental package | Loading and crash testing remains unfinished; it is not a recommended upgrade path. |
| 0.6.4 through 0.12.35 | GitHub-only best-effort, finite data-only packages | No mod settings, runtime features, Library or save migrations; these builds have not been tested in-game for MIR 5. Packages for 0.6 through 0.8 must be extracted into the mods folder. |
| 0.1.2 through 0.5.3 | No package | The required engine or prototype inputs are unavailable. |

- Minimums for the seven older builds: **0.6.4**, **0.7.5**, **0.8.8**, **0.9.8**, **0.10.12**, **0.11.22** and **0.12.35**.
- Best-effort packages do not extend normal support. Preserve your original save and installation files before trying one.

## First upgrade

- Before changing MIR or Factorio:

- Back up the save, installed mods and startup settings.
- Test a copy with the same Factorio family and matching mod set first.
- Keep inherited settings for the first load.
- Inspect earned bonuses, current research, queued or paused work, caps and research supplied by other mods.
- Save the copy under a new name, then close and reload it before adopting the upgrade.

- Published MIR 4.7.3 upgrades have recorded results within their stated conditions for these cross-version paths:

| From Factorio | To Factorio | Recorded scope |
| --- | --- | --- |
| 1.0 | 1.1 | Published-save upgrade with retained research and useful follow-up research. |
| 1.0 | 2.1 | Published-save upgrade with retained research and useful follow-up research. |
| 1.1 | 2.1 | Published-save upgrade with retained research and useful follow-up research. |
| 2.0 Base game | 2.1 Base game | Published-save upgrade with retained Base-game research and state. |

- These routes do not automatically cover different expansion, provider, startup-setting or mod combinations. Older histories and best-effort editions retain their stated limits. A successful load is not proof that every earned effect or queued research state was preserved.

### Productivity providers and preferences

- Use this additional caution only for a Factorio 2.0 save from MIR 4.7 with overlapping productivity from a known provider when you plan to change that provider, MIR's preference or relevant startup settings, especially as part of a move from Factorio 2.0 to 2.1:

1. Keep the original Factorio version, enabled mods and startup settings.
2. Upgrade the copied save to the matching MIR 5 package.
3. Inspect research and effects, save the copy and reload it.
4. Only then change the provider, preference, settings or Factorio version.

- MIR can refuse this first upgrade when it cannot determine a safe productivity preference. Do not remove a provider or change settings merely to force an upgrade through.

### Same-edition and historical upgrades

- Recorded same-edition cases cover retained research, effects, partial work and reload behavior for the normal Factorio families. The observed 2.1 cases include Base and selected Space Age content; the observed 2.0 cases include Base and a selected provider/preference boundary. Earlier editions have narrower historical state coverage. Treat a different modpack, setting, provider or DLC change as its own case.

- MIR preserves earned levels when a cap later limits future work. It only reverses a disablement it recorded itself; another mod can independently change a technology's availability. Hidden supporting technologies can preserve historical investments and should not be removed as cosmetic clutter.

- Use the Research Library on Factorio 2.0 and 2.1 to inspect research, queues, settings and availability. Search, filters and language preferences are personal. The Library uses Factorio's built-in research queue; it is not a second research planner.

## Observed same-edition upgrade cases

| Factorio family | Recorded player-facing boundary |
| --- | --- |
| 2.1 | Base and selected Space Age research, queued or detached work, new research, save and reload. |
| 2.0 | Base research and saved work, plus a selected provider/preference transition. |
| 1.1 and 1.0 | Retained research/effects, queue or partial work where supported, useful follow-up research and reload. |
| 0.13 through 0.17 | Historical mining/state preservation within each engine's capability subset. |

- These are scoped observations, not universal modpack, provider, multiplayer or performance guarantees. See [progress](progress.md) for technical qualification detail.

## Requested published cross-edition routes

- The four published cross-edition routes above are closed within their recorded scopes. Keep direct mod upgrades, engine changes, DLC changes, provider changes and startup-setting changes separate so a problem can be identified safely.

- When a route is outside those scopes, preserve the original save and ask for support before changing more than one variable. Do not recreate a historical save or install MIR on an intermediate engine unless Factorio itself requires a bridge.

## Researched planet still locked

- MIR preserves ambiguous locks rather than deciding that another mod was wrong. If you deliberately need a one-time repair for an official Space Age planet on Factorio 2.1 with Space Age enabled, use a copy of the save and first confirm that no enabled mod intends the lock.

- Lua console commands disable achievements for that save. This example checks the current player's force and Vulcanus only when its researched technology contains the matching native unlock effect:

```lua
/c local f=game.player.force; local n="vulcanus"; local t=f.technologies["planet-discovery-"..n]; for _,e in pairs(t and t.researched and t.prototype.effects or {}) do if e.type=="unlock-space-location" and e.space_location==n and not f.is_space_location_unlocked(n) then f.unlock_space_location(n) end end
```

- Replace `vulcanus` with `gleba`, `fulgora` or `aquilo` for another official discovery. On a server, replace `game.player.force` with `game.forces["force-name"]` for the intended force. If the technology has no matching effect, the command does nothing; keep the save and report the configuration instead of granting research manually.

## Recovery from the 4.2.1 incident

- This is historical recovery guidance, not an MIR 5 upgrade result.

- Upgrade directly from MIR 4.2.0 or 4.2.1 to the [4.2.2 hotfix](https://github.com/Julesc013/more-infinite-research/releases/tag/v4.2.2); do not install 4.2.1 as an intermediate step.
- Keep the original save and a pre-update backup.
- If you saved after 4.2.1 removed research, load a copy of the pre-update backup directly with 4.2.2. Reinstalling a definition cannot recreate levels or bonuses already erased from a resaved file.
- Do not remove MIR or downgrade an already-resaved factory as an assumed recovery.

- See [issue #621](https://github.com/Julesc013/more-infinite-research/issues/621) and the [hotfix notes](https://github.com/Julesc013/more-infinite-research/releases/download/v4.2.2/release-notes.md) for the historical fix.

## Safe diagnosis

- Before reporting a problem, preserve the original save and reproduce it on a copy where possible. Include:

- Factorio version, MIR version and enabled mod list;
- relevant startup settings or a full exported settings profile;
- clear expected and observed behavior;
- repeatable steps, plus a save only when it is safe to share;
- `factorio-current.log` and any crash message, after removing secrets and private paths.

- On Factorio 2.0/2.1, Library **Export Settings** creates a full settings profile. Use this for support requests.
- **Export Compact** omits defaults; it can behave differently after defaults change in a later version.
- Use `/mir-settings-export` or `/mir-settings-export --compact` for the same exports through chat/console.
- Find the settings file at `script-output/more-infinite-research/settings/mir-settings-profile.txt` in Factorio's user-data folder.
- Check a shared string with `/mir-settings-import-check <profile-string>` before choosing to use it.
- To apply it, paste the string into the `mir-settings-profile-import` startup setting and restart Factorio.
- Exporting and checking a profile never applies settings or changes research. Profiles do not back up other mods, map settings or research.

- **Export Diagnostics** or `/mir-diagnostics-export` replaces the latest support report at `script-output/more-infinite-research/mir.log` and exports the full settings profile.
- Attach `factorio-current.log` separately for startup or crash problems; MIR cannot copy the engine log.
- File-write errors leave gameplay unchanged. A partial export may still leave its already-written settings file.

- Exports stay local and are never uploaded automatically. Review them before sharing: settings metadata can include your player name, and engine logs can include usernames and local paths.

## Support limits

- MIR does not claim universal modpack support. Results apply to their actual Factorio version, MIR package, mod set, settings, save and action. A safe outcome may be a workaround, a request for a reproducible save, a documented limitation or a refusal to change ambiguous saved state.

## Performance claims

- Performance testing for the first beta is unfinished. Earlier observations belong only to their recorded packages, engines and workloads; do not expect a particular startup, memory or factory-performance improvement from a different setup or final package.

- Whole-game startup, save loading, Library use and factory simulation are separate measurements. A successful load, a smaller package or one quick scenario is not a general performance result. See the release notes for known limits. Detailed test records are in [developer progress](progress.md).
