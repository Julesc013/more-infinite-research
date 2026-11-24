-- Stable native identities for a prepared provider removal. The data-stage
-- rows alone never claim a force's research or make it available to players.
local copy_owner = require("research.worker_storage_recovery").copy_owner
local M = {}

M.profiles = {
  {
    target = "f210", prerequisite_mod = "space-age",
    provider = "planet-ferrum", version = "0.1.5",
    stages = {
      {source="worker-robots-storage-5", first=5, last=5, count=1012,
        holder="mir-worker-storage-ferrum-hold-5", debit="mir-worker-storage-ferrum-debit-1"},
      {source="worker-robots-storage-6", first=6, last="infinite", previous_count=675, predecessor_count=1012,
        holder="mir-worker-storage-ferrum-tail-hold-6", debit="mir-worker-storage-ferrum-tail-debit-1"},
    },
    -- Factorio retains queue positions if the holder's prerequisite remains
    -- satisfied. The provider's finite public4 becomes MIR's infinite4.
    prerequisite = "worker-robots-storage-3", seconds = 60, modifier = 1,
  },
}

local function work_source(technology)
  local effect = technology and technology.effects and technology.effects[1]
  return effect and #technology.effects == 1 and effect.type == "worker-robot-storage"
    and type(effect.modifier) == "number" and effect.modifier >= 0 and technology.unit ~= nil
end

function M.terms(profile, stage, stream)
  local count_formula
  if stage.count == nil then
    count_formula = require("research.cost").continuation(stream, stage.first, stage.predecessor_count, stage.previous_count)
  end
  return stage.count, count_formula,
    not stage.count and stream.research_time > 0 and stream.research_time or profile.seconds,
    stage.count and profile.modifier or profile.modifier * stream.effect_percent
end

local function archive_holder(profile, stage, presentation, stream, source)
  local count, formula, seconds, modifier = M.terms(profile, stage, stream)
  local unit = {count=count, count_formula=formula, time=seconds, ingredients=presentation.unit.ingredients}
  local holder = {
    type="technology", name=stage.holder, level=stage.first, max_level=stage.last, upgrade=true,
    hidden=true, enabled=false, visible_when_disabled=false,
    icon=presentation.icon, icon_size=presentation.icon_size, icons=presentation.icons,
    localised_name=presentation.localised_name, localised_description=presentation.localised_description,
    prerequisites={profile.prerequisite},
    unit=source and source.unit or unit,
    effects=source and source.effects or {{type="worker-robot-storage", modifier=modifier}},
    ignore_tech_cost_multiplier=source and source.ignore_tech_cost_multiplier or false,
  }
  local debit = {
    type="technology", name=stage.debit, level=1, max_level="infinite", upgrade=true,
    hidden=true, enabled=false, visible_when_disabled=false,
    icon=presentation.icon, icon_size=presentation.icon_size, icons=presentation.icons,
    localised_name=presentation.localised_name, prerequisites={},
    unit={count=1, time=1, ingredients={presentation.unit.ingredients[1]}},
    effects={{type="worker-robot-storage", modifier=source and -holder.effects[1].modifier or 0}},
    ignore_tech_cost_multiplier=true,
  }
  -- The entries are independent publication inputs. A different mod's
  -- prototype table and the authored default cannot become writable aliases.
  return copy_owner(holder), copy_owner(debit)
end

function M.append(technologies, raw, active, target, presentation, stream, route)
  for _, profile in ipairs(M.profiles) do
    if target == profile.target and active[profile.prerequisite_mod]
        and raw.technology[profile.prerequisite] then
      local endpoint = profile.stages[#profile.stages].source
      local tail
      if active[profile.provider] == profile.version and route and route.owned and route.technology == endpoint then
        for _, technology in ipairs(technologies) do
          if technology.name == endpoint then tail = technology; break end
        end
      end
      for _, stage in ipairs(profile.stages) do
        local source = tail and (stage.source == endpoint and tail or raw.technology[stage.source])
        if not work_source(source) then source = nil end
        local holder, debit = archive_holder(profile, stage, presentation, stream, source)
        technologies[#technologies + 1] = holder
        technologies[#technologies + 1] = debit
      end
    end
  end
end

return M
