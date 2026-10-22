# Player source boundary

This directory reserves the single replacement player-source root. **It contains no installable MIR implementation yet.** Do not package this README as a mod, create empty lifecycle files, or infer feature parity from its presence.

Implement approved native slices here using [the Generator contract](../../spec/mir5/generator.md), [determinism](../../spec/mir5/determinism.md) and the [API contract](../../spec/mir5/api.md). Native imports/asset paths are package-relative and never contain the checkout prefix. Production code must not import the former compiler or developer SDK.

A partial development package is safe only for its disposable fixture worlds. Required full historical identities must be present before upgrading real full-catalogue saves. This README becomes `source/README.md` at the mechanical cutover and remains package-excluded.
