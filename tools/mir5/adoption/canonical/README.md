# More Infinite Research

Configurable repeatable research for vanilla and supported modded Factorio content. Research definitions, settings and save continuity are maintained as explicit contracts.

Use an accepted release matching your Factorio family and its declared patch minimum. A development checkout or a successful host test is not a qualified player release. Preserve backups before upgrading; removing the mod or downgrading a resaved factory is not an assumed recovery.

| Need | Entry point |
|---|---|
| Player support and upgrade boundaries | [Support](docs/support.md) |
| Design | [Design summary](docs/design.md) |
| Implementation and contribution | [Development](docs/development.md) |
| Normative requirements | [Specification index](spec/README.md) |
| Mod integration | [MIR API](docs/api.md) and [SDK](sdk/README.md) |

Player source is in `source/`; target-specific differences are in `targets/`. Tests, SDK, documentation and developer tools are not installed into the game. The Generator constructs authored technologies during Factorio's data stage; necessary scripted effects and the Research Library remain separate runtime modules.

Support and performance claims must identify their tested scope. The complete release-specific changelog and package metadata accompany each distribution. GitHub and Mod Portal availability are separate observations.
