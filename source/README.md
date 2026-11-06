# Player source

`source/` is the single editable player implementation. To build a local ZIP, start with the [development guide](../docs/development.md#build-a-local-zip). Tests, build tools and contributor documentation stay outside the player package; this README is excluded too.

The startup path is: effective configuration and selected integrations → authored technology construction → Generator validation and publication. Factorio owns ordinary research and its native effects. Runtime callbacks handle caps, earned contributions, scripted effects and the Research Library.

## Find a feature

| What you want to change | Start here |
|---|---|
| Setting definitions, imports or effective values | [settings.lua](settings.lua), [research/settings.lua](research/settings.lua), [research/settings_profile.lua](research/settings_profile.lua) |
| Research definitions and startup composition | [research/catalogue.lua](research/catalogue.lua), the related `research/` modules, [data-final-fixes.lua](data-final-fixes.lua) |
| Validation and publication of already-built technologies | [research/generator.lua](research/generator.lua) |
| Overhaul bindings and recipe targets | `compatibility/`, related definitions in `research/`; the RIC integration is grouped under `integrations/ric/` |
| Explicit changes to existing prototypes | `overrides/` |
| Runtime event registration | [control.lua](control.lua), [runtime/bootstrap.lua](runtime/bootstrap.lua) |
| Caps and preservation of earned contributions | [runtime/lifecycle.lua](runtime/lifecycle.lua), [runtime/native_credits.lua](runtime/native_credits.lua), [runtime/native_gun_credits.lua](runtime/native_gun_credits.lua) |
| Repair, agriculture or spoilage | [runtime/passive_repair.lua](runtime/passive_repair.lua), [runtime/scripted_effects.lua](runtime/scripted_effects.lua) |
| Library rendering, input or personal state | [runtime/library.lua](runtime/library.lua), the `runtime/library_*` and `presentation/library_*` modules |
| Engine differences | [platform/target.lua](platform/target.lua), `adapters/` |
| Public integration API | [api/v1/data.lua](api/v1/data.lua), [api/v1/runtime.lua](api/v1/runtime.lua), and the [API guide](../docs/api.md) |
| Save migrations, translations or release history | `migrations/`, `locale/`, and the authored [root changelog](../CHANGELOG.md), which generates `changelog.txt` |

The [architecture guide](../docs/architecture.md#where-to-change-a-feature) explains the current module boundaries, saved-state owners and planned Library move. Its destination paths are a move plan; the table above points to files that exist now.

## Make a change

Keep package-relative imports, published technology/setting/API identities, saved-state keys and migration filenames intact. Use the relevant [task contract](../spec/README.md#task-routing) and [affected checks](../docs/development.md#test-selection). The Generator validates a finite submitted family and publishes it once; compatibility collection and optional broad overrides remain separate.

Test development packages on copies of saves with their matching mods and settings. The [support guide](../docs/support.md) describes supported configurations; [current progress](../docs/progress.md) distinguishes accepted results from remaining work. A ZIP build or host pass alone does not establish gameplay, upgrade safety or performance.

The nine stable editions share this source. The [target contract](../spec/targets.md#additional-historical-editions) separately describes experimental Factorio 0.18.47 and best-effort early builds: F006–F012 have fixed finite defaults and no settings, runtime API, Library or migrations; F001–F005 remain unresolved. Edition metadata selects capabilities rather than another editable source tree.
