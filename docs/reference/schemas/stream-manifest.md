---
title: "Generated Stream Manifest And Migration Policy"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# Generated Stream Manifest And Migration Policy

Updated: 2026-07-07

Generated technology IDs are save-compatibility surface area. Once released,
they must be treated like an API.

## Manifest Purpose

The stream manifest records stable generated IDs, capability ownership, target
recipes, and migration policy:

```json
{
  "schema": 1,
  "streams": {
    "mir-prod-air-scrubbing-clean-filter": {
      "introduced_in": "2.2.0",
      "status": "stable",
      "capability": "recipe-productivity.clean-filter",
      "family": "clean_filter",
      "policy": "air-scrubbing.clean-filter",
      "technology": "research_air_scrubbing_clean_filter_productivity",
      "stream_key": "air_scrubbing_clean_filter_productivity",
      "targets": [
        "atan-pollution-filter",
        "atan-spore-filter"
      ],
      "migration_policy": "preserve"
    }
  }
}
```

## Rules

- Every generated stream has a manifest row before release.
- Stable stream IDs do not change after release without a migration.
- Removed streams become hidden, migrated, or explicitly documented.
- Renamed technologies need JSON or Lua migrations where Factorio supports them.
- Target-list changes require report-diff review.
- Missing optional targets should produce diagnostics, not load failure.
- Manifest rows should include the version that introduced the stream.

## Migration Policies

| Policy | Meaning |
| --- | --- |
| `stable` | Preserve ID and behavior unless a new manifest row supersedes it. |
| `preserve` | Keep researched progress even if target list changes. |
| `rename_with_migration` | Rename only with a committed migration. |
| `hide_legacy` | Keep old tech hidden to preserve saves. |
| `remove_unreleased` | Allowed only before a public release. |

## Release Checklist

Before release:

- manifest linter passes;
- every generated technology has a manifest row;
- every manifest row references an existing generator or documented legacy tech;
- every rename/removal has a migration or explicit unreleased status;
- package validation includes migrations when needed;
- release notes mention user-visible generated technology changes.
