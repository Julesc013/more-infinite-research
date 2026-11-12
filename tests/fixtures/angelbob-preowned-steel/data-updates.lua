-- Controlled foreign ownership, not a claim about the reporter's mod selection.
-- Add legitimate native effects before MIR's final preflight, without changing
-- the owner identity, ordinary cost, science, flags or any recipe prototype.
assert(mods.base == "2.1.23" and mods["angelbob-spaceage-rebalance"] == "1.3.2")
local owner = assert(data.raw.technology["steel-plate-productivity"])
local named = {"angels-plate-steel", "angels-plate-steel-2"}
local original = {["steel-plate"]=0, ["casting-steel"]=0}
for _, effect in ipairs(owner.effects or {}) do
  if effect.type == "change-recipe-productivity" then
    if original[effect.recipe] ~= nil then
      assert(effect.change == .1, "original steel scalar differs")
      original[effect.recipe] = original[effect.recipe] + 1
    end
    assert(effect.recipe ~= named[1] and effect.recipe ~= named[2], "witness requires unextended native owner")
  end
end
assert(original["steel-plate"] == 1 and original["casting-steel"] == 1)
for _, name in ipairs(named) do assert(data.raw.recipe[name], "witness recipe is absent: " .. name) end
for _, name in ipairs(named) do
  owner.effects[#owner.effects + 1] = {type="change-recipe-productivity", recipe=name, change=.1}
end
log("[MIR_STEEL_PREOWNED_WITNESS] Two explicit foreign effects installed before MIR; controlled scenario only")
