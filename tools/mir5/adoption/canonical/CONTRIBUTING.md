# Contributing

Read [AGENTS.md](AGENTS.md) for repository safeguards and [development guidance](docs/development.md) for bounded tasks. These rules apply to humans and coding agents alike.

Keep a change focused on one observed defect or accepted feature. Identify the existing requirement/incident, affected target/profile/settings and exact expected result. Prefer ordinary Lua and native Factorio mechanisms. New abstractions require actual reuse or a concrete safety boundary.

Tests should reject plausible mistakes, not simply count executed assertions. Run the affected host/native checks and retain failures and unavailable-input states. A changed expected result requires independent evidence. Preserve saved identities, earned effects, partial progress and unrelated state.

Submit a reviewable branch/PR to `dev`. Do not alter the public release or repository controls as part of ordinary work. Keep third-party licenses, attribution and archive custody. Do not commit game binaries, copied upstream mod archives, huge logs or sensitive local paths/credentials.

No contributor may declare arbitrary future mod combinations safe or a performance gain without matched measurement. Release claims follow the actual accepted package and evidence.
