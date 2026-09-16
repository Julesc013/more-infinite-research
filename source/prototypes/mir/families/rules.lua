-- Compatibility adapter. CompilerProvider is the extension boundary; FamilyRule
-- remains the pure planner input consumed by the existing resolver. Adapter
-- output retains the released schema authority marker: schema = 2.
return require("prototypes.mir.providers.registry").family_rule_source()
