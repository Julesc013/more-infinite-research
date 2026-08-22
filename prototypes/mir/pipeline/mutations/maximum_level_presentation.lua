local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local compiler_orchestrator = require("prototypes.mir.pipeline.compiler_orchestrator")
local maximum_level_binding = require("prototypes.mir.domain.technology.maximum_level_binding")

local M = {}

local function finite_maximum(value)
  local maximum = tonumber(value)
  if not maximum or maximum <= 0 then return nil end
  return math.floor(maximum)
end

local function technology_name(technology)
  return technology.localised_name or {"technology-name." .. tostring(technology.name)}
end

local function cap_label(source, technology)
  if source == "base-continuation" then
    return {"mod-setting-name.mir-max-level", technology_name(technology)}
  end
  return {"mod-setting-name.ips-max-level-stream", technology_name(technology)}
end

local function append_cap_description(technology, source, maximum)
  local description = technology.localised_description
  local prefix = description and {"", description, "\n"} or {""}
  table.insert(prefix, cap_label(source, technology))
  table.insert(prefix, ": ")
  table.insert(prefix, tostring(maximum))
  return prefix
end

function M.apply(context)
  local policy = compiler_orchestrator.maximum_level_policy(context)
  local applied, blocked, observations = {}, {}, {}
  for _, binding in ipairs(policy.bindings or {}) do
    local technology = data_raw.technology(binding.technology_id)
    local observed = technology and technology.max_level or "missing"
    local maximum = finite_maximum(binding.cap and binding.cap.effective)
    if maximum and technology and binding.diagnostics.status ~= "blocking-conflict" then
      if observed == "infinite" then
        technology.show_levels_info = binding.presentation_strategy.show_levels_info
        technology.visible_when_disabled = binding.presentation_strategy.visible_when_disabled
        technology.localised_description = append_cap_description(
          technology, binding.binding.source, maximum)
        table.insert(applied, binding.technology_id .. "=" .. tostring(maximum))
      else
        table.insert(blocked, binding.technology_id)
        log("[more-infinite-research] Maximum-level presentation refused"
          .. " technology=" .. tostring(binding.technology_id)
          .. " selected=" .. tostring(maximum)
          .. " final-observed=" .. tostring(observed)
          .. " reason=late_prototype_maximum_conflict.")
      end
    elseif maximum and (not technology or binding.diagnostics.status == "blocking-conflict") then
      table.insert(blocked, binding.technology_id)
      log("[more-infinite-research] Maximum-level presentation refused"
        .. " technology=" .. tostring(binding.technology_id)
        .. " selected=" .. tostring(maximum)
        .. " final-observed=" .. tostring(observed)
        .. " reason=" .. tostring(binding.diagnostics.active_code
          or "maximum_level_finalizer_observation_missing") .. ".")
    end
    observations[binding.technology_id] = {
      adapter = policy.finalizer_adapter,
      observed_prototype_max_level = observed
    }
  end
  local observed_policy = maximum_level_binding.observe_finalizers(policy, observations)
  context:replace_epoch(
    "maximum_level_policy", observed_policy, context:state_epoch("maximum_level_policy"))
  log("[more-infinite-research] Applied truthful finite-cap presentation"
    .. " count=" .. tostring(#applied)
    .. " blocked=" .. tostring(#blocked)
    .. " technologies=" .. table.concat(applied, ",") .. ".")
end

return M
