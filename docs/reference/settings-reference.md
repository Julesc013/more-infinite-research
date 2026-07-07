---
title: "Settings Reference"
status: draft
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Settings Reference

This page is the maintainer-level home for startup setting keys, defaults,
allowed values, and behavior contracts. Player-facing guidance belongs in
[user settings](../user/settings.md).

Until this page is expanded, the canonical implementation is `settings.lua` and
`defaults.lua`.

## Technology Setting Visibility

MIR defines per-technology startup settings even when a technology is not useful
in the current mod set, so existing saves, copied settings files, and backports
can keep stable setting keys.

For user-facing noise control, the settings generator may mark the full
per-technology setting group as `hidden = true` when stream metadata declares
required active mods and those mods are not enabled. This applies to the enable,
base cost, growth, maximum-level, and research-time settings for that stream.

Visibility is settings-stage policy only:

- `required_mods` still controls data-stage generation skips;
- `settings_required_mods` controls startup-setting visibility without changing
  generation behavior;
- hidden settings remain defined settings, not removed settings;
- the visibility policy can use Factorio's active `mods` table during settings
  stage, but it cannot inspect `data.raw` recipe, item, fluid, or technology
  prototypes because those are finalized later.

Use `settings_required_mods` for compatibility streams whose fixture mods do
not use the same mod ID as the real target. Use `required_mods` when the stream
must also skip generation without that mod.
