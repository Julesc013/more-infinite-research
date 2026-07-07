---
title: "Settings"
status: current
applies_to: "3.0.0+"
audience: player
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Settings

MIR uses startup settings for generated technology enablement, costs, caps,
science-pack policy, diagnostics, and prototype-stage options. Startup settings
are read during Factorio's prototype loading stages, so most generation choices
require a restart after changing them.

Some technology settings are hidden when their required mod or DLC is not
enabled. MIR still defines those setting keys internally so copied settings,
existing saves, and target-line backports can keep stable values. If the
relevant mod or expansion is enabled later, the setting can become visible
again with the saved value still available.

Use the in-game setting descriptions for exact defaults. Use
[settings reference](../reference/settings.md) for the canonical
technical contract once a setting needs maintainer-level detail.
