-- A deliberately narrow actor used only by the integration-upgrade witness.
-- It owns one disabled flag and exposes no technology discovery or repair API.
local KEY = "mir5_integration_foreign_owner"
local INTERFACE = "mir5-integration-foreign-owner"
local FOREIGN_FORCE = "mir5-integration-catalogue-upgrade-foreign"
local PRIMARY = {
  ["recipe-prod-research_armor_components-1"] = true,
  ["recipe-prod-research_material_py_log-1"] = true,
  ["recipe-prod-research_breeding-1"] = true,
}

local function fail(message)
  error("[mir5-integration-foreign-owner] " .. message)
end

remote.add_interface(INTERFACE, {
  record_and_disable = function(force_index, technology_name)
    if storage[KEY] ~= nil then fail("actor state already exists") end
    if type(force_index) ~= "number" or force_index ~= math.floor(force_index) or force_index < 1 then
      fail("foreign force identity differs")
    end
    if PRIMARY[technology_name] ~= true then fail("technology is outside the integration primary set") end
    local force = game.forces[force_index]
    if force == nil or force.valid == false or force.name ~= FOREIGN_FORCE then fail("foreign force differs") end
    local technology = force.technologies[technology_name]
    if technology == nil or technology.valid == false or technology.name ~= technology_name then
      fail("named primary technology is absent")
    end
    if technology.enabled ~= true then fail("named primary is not initially enabled") end
    technology.enabled = false
    if technology.enabled ~= false then fail("named primary disablement did not persist") end
    storage[KEY] = {force_index=force_index, technology=technology_name, disabled=true}
  end,
})
