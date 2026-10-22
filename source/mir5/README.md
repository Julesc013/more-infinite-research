# Player source boundary

This directory contains the selected replacement player-source implementation. Its first package is an **incomplete private gear-research slice for disposable test worlds**. Full product parity and release qualification are pending. Do not package this README as a mod or use this slice to upgrade a production save.

Implement approved native slices here using [the Generator contract](../../spec/mir5/generator.md), [determinism](../../spec/mir5/determinism.md) and the [API contract](../../spec/mir5/api.md). Native imports/asset paths are package-relative and never contain the checkout prefix. Production code must not import the former compiler or developer SDK.

A partial development package is safe only for its disposable fixture worlds. Required full historical identities must be present before upgrading real full-catalogue saves. This README becomes `source/README.md` at the mechanical cutover and remains package-excluded.

Build only this explicitly selected subtree with `python tools/mir5/package.py --source source/mir5 --output <canonical-name.zip>`. The current slice supports vanilla F210 gear research with the published default or tuned cost/effect settings, declared profile-import precedence and native construction. Finite caps retain the native infinite identity and use an event-driven runtime preservation controller. The controller and draft data/runtime API have focused host controls; native integration acceptance remains pending. Broader science policies, other research, overrides, scripted features, Library and historical targets remain pending.
