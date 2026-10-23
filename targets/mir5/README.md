# Target boundary

The [target specification](../../spec/mir5/targets.md) lists the inherited nine-edition baseline and its qualification limits. [editions.json](editions.json) now selects private source composition, engine-family metadata and baseline patch floors. Exact MIR5 qualification remains pending for the historical editions. The F200 source adaptation remains incomplete and explicit package selection refuses it.

Add only actual differences in metadata, syntax, native effects or runtime interfaces. Keep shared research source singular. Select one applicable adapter per self-contained player package. Tooling may use a modern host without restricting the target Factorio engine. Existing target version encoding is preserved unless separately reviewed.

The reduced adapter uses the shared eleven native-effect declarations and preserves the observed Base subsets: 7/7/9/10/11/11/11 technologies for F013/F014/F015/F016/F017/F100/F110. Its settings, science, prerequisites, icons, costs and finite limits are selected by actual target contracts. The portable historical native-state fixture characterizes earlier MIR4 behavior; the retained historical 4.7 candidate ZIPs do not establish a published or qualified MIR5 output.

`tools/mir5/package.py --target f015` selects the reduced stage adapters, their actual Lua import closure and target metadata, and derives `5.0.01500` from source `5.0.21000`. A committed build binds the edition record at the same revision as player source. Source-only composition checks do not establish gameplay, upgrades or a release claim.

At cutover this directory becomes `targets/`. Native player member paths remain unchanged.
