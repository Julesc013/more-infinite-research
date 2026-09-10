local technologies = {
  "recipe-prod-research_material_rare_metals-1",
  "recipe-prod-research_material_silicon-1",
  "recipe-prod-research_material_glass-1"
}
local function fail(message) error("MIR A05 K2 material continuity failed: " .. message) end
script.on_init(function()
  storage.mir4_a05_k2_materials = {}
  for index, name in ipairs(technologies) do
    local force_name = "mir-a05-k2-material-" .. tostring(index)
    local force = game.create_force(force_name)
    force.research_all_technologies()
    local technology = force.technologies[name]
    if not technology then fail("generated technology absent " .. name) end
    technology.level = 1
    force.research_queue = {technology}
    if not force.current_research or force.current_research.name ~= name then fail("partial research unavailable " .. name) end
    force.research_progress = 0.42
    storage.mir4_a05_k2_materials[#storage.mir4_a05_k2_materials + 1] = {force=force_name,technology=name,level=technology.level,progress=0.42}
  end
end)
script.on_event(defines.events.on_tick, function()
  local rows = storage.mir4_a05_k2_materials
  if not rows then return end
  for _, row in ipairs(rows) do
    local force = game.forces[row.force]
    local technology = force and force.technologies[row.technology]
    if not technology or technology.level ~= row.level or not force.current_research or force.current_research.name ~= row.technology or math.abs(force.research_progress - row.progress) > 0.0001 then
      fail("partial research did not survive load " .. row.technology)
    end
    log("[MIR4_A05_K2_MATERIAL_PROGRESS] force=" .. row.force .. ";technology=" .. row.technology .. ";progress=0.42")
  end
  storage.mir4_a05_k2_materials = nil
end)