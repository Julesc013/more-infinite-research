---
title: "MIR 5.0.17 beta release notes"
status: current
applies_to: "MIR 5.0.17 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-17
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-517-release-notes
---

Repairs a worker-cargo upgrade refusal for inherited MIR 5.0.11 saves and improves Research Library details and internal error handling.

- Allow inherited MIR 5.0.11 saves previously using only Base and MIR to upgrade after startup settings change or mods are added, when no worker-cargo continuation research has been earned, started or queued on any force.
- Apply the configured worker robot speed limit to Space Exploration's infinite research beginning at level 10.
- Avoid invalid GUI style reads when refreshing the Library's Settings tab.
- Distinguish finite and continuing research with the same localized name, including their effective limits.
- Reject incomplete internal preservation interfaces before changing research, and retain unexpected integration errors instead of misreporting them as missing research or history.

Update a copy first and keep the protected original with its matching mods and startup settings. This worker-cargo repair covers a verified empty inherited 5.0.11 history; it does not reconstruct unknown earned research or every earlier mod selection. Other unprepared older saves can still be refused. Removing MIR, saving and re-adding it can discard research and preservation data; use an original backup or a supported recovery route instead.

This is a GitHub beta. Remaining Library input/export checks, broader performance testing and unresolved historical save cases remain open for stable MIR 5. No blanket save or modpack qualification is claimed.

[Installation, upgrade precautions and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.17/docs/support.md).
