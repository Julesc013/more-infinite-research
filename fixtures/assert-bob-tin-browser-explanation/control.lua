local technology_name = "recipe-prod-research_material_tin-1"
local recipe_name = "bob-tin-plate"
local non_recipe_name = "mir-browser-non-recipe-regression"
local duplicate_name = "mir-browser-duplicate-row-regression"
local wrong_schema_name = "mir-browser-wrong-schema-row-regression"
local extra_field_name = "mir-browser-extra-field-row-regression"
local core = require("__more-infinite-research__/prototypes/mir/runtime/research_browser_core")
local catalogue_adapter = require("__more-infinite-research__/prototypes/mir/runtime/research_browser_factorio_catalogue")
local provider = require("__more-infinite-research__/prototypes/mir/runtime/research_browser_mir_provider")

local function fail(message) error("[mir-bob-tin-browser-explanation] " .. message) end
local function check(value, message) if not value then fail(message) end end
local function contains(text, expected) return type(text) == "string" and string.find(text, expected, 1, true) ~= nil end

local function force_snapshot(force)
  local technology = force.technologies[technology_name]
  local queue = {}
  for index, entry in ipairs(force.research_queue or {}) do queue[index] = entry.name end
  return helpers.table_to_json({
    level = technology and technology.level,
    researched = technology and technology.researched,
    current = force.current_research and force.current_research.name or nil,
    progress = force.research_progress,
    queue = queue
  })
end

local function capture_facts(element, out)
  if not element or not element.valid then return end
  local tags = element.tags
  if tags and type(tags.mir_browser_fact) == "string" then out[tags.mir_browser_fact] = element.caption end
  for _, child in pairs(element.children or {}) do capture_facts(child, out) end
end

local function detail_for(force)
  local catalogue = catalogue_adapter.snapshot(force)
  check(catalogue and catalogue.schema == 1, "Factorio catalogue adapter did not return a copied DTO")
  local enrichment = provider.snapshot(force)
  check(enrichment and enrichment.schema == 2 and enrichment.kind == "portable-research-enrichment", "provider did not return schema-2 portable enrichment")
  local detail, reason = core.detail(catalogue, technology_name, enrichment)
  check(detail and reason == nil and detail.enrichment, "portable core did not copy Tin detail")
  return catalogue, enrichment, detail
end

local function deep_copy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, child in pairs(value) do copy[key] = deep_copy(child) end
  return copy
end

local function valid_synthetic_enrichment()
  return {
    schema = 2,
    kind = "portable-research-enrichment",
    caps = {[technology_name] = 3},
    families = {[technology_name] = "research_material_tin"},
    details = {
      [technology_name] = {
        schema = 1,
        family = "research_material_tin",
        action = "emit",
        owner = {
          technology_id = technology_name,
          stream_id = "research_material_tin",
          action = "emit",
          reason = "emit",
          affected_recipe_ids = {recipe_name}
        },
        compiler_disposition = {
          inclusion = "included",
          action = "emit",
          reason = "emit",
          route_exclusions = {
            state = "no-additional-route-exclusions-published-for-current-row",
            recipe_ids = {}
          }
        },
        final_science = {
          rationale = "fixture",
          ingredients = {{name = "automation-science-pack", amount = 1}}
        },
        effective_cap = 3,
        current_level = 3,
        recipe_benefits = {{
          recipe_id = recipe_name,
          effect_change = 0.02,
          current_productivity_bonus = 0,
          maximum_productivity = 1,
          next_level_has_effective_benefit = true
        }},
        next_level_has_effective_benefit = true,
        settings = {
          maximum_level = {
            name = "ips-max-level-research_material_tin",
            default = 2,
            raw_direct = 2,
            effective = 3,
            source = "mirset1",
            changed = true,
            changed_from_default = true,
            restart_required = true
          },
          enabled = {
            name = "ips-enable-research_material_tin",
            default = true,
            raw_direct = true,
            effective = true,
            source = "mirset1",
            changed = false,
            changed_from_default = false,
            restart_required = true
          }
        }
      }
    }
  }
end

local function assert_fake_and_limit_negatives(catalogue)
  local fake = {
    schema = 2,
    kind = "portable-research-enrichment",
    caps = {[technology_name] = 3},
    families = {[technology_name] = "research_material_tin"},
    details = {[technology_name] = {schema = 1, family = "research_material_tin", action = "emit", fake = true}}
  }
  local fake_detail = core.detail(catalogue, technology_name, fake)
  check(fake_detail and fake_detail.enrichment == nil, "malformed fake provider envelope was accepted")
  local wrong_kind = {
    schema = 2,
    kind = "untrusted-browser-facts",
    caps = {}, families = {}, details = {}
  }
  local wrong_detail = core.detail(catalogue, technology_name, wrong_kind)
  check(wrong_detail and wrong_detail.enrichment == nil, "fake provider kind was accepted")
  local oversized = {
    schema = 2,
    kind = "portable-research-enrichment",
    caps = {[technology_name] = 3},
    families = {[technology_name] = "research_material_tin"},
    details = {[technology_name] = {payload = string.rep("x", core.detail_string_limit + 1)}}
  }
  local result, reason = core.detail(catalogue, technology_name, oversized)
  check(result and result.enrichment == nil and reason == nil, "oversized provider detail did not fail closed")
  local cross_bound = {
    schema = 2, kind = "portable-research-enrichment",
    caps = {[technology_name] = 3}, families = {[technology_name] = "research_material_tin"},
    details = {[technology_name] = {schema = 1, family = "research_material_tin", action = "emit",
      owner = {technology_id = "wrong-technology", stream_id = "research_material_tin", action = "emit", reason = "emit", affected_recipe_ids = {}},
      compiler_disposition = {inclusion = "included", action = "emit", reason = "emit", route_exclusions = {state = "no-additional-route-exclusions-published-for-current-row", recipe_ids = {}}},
      final_science = {rationale = "fixture", ingredients = {}}, effective_cap = 3, current_level = 1,
      recipe_benefits = {}, next_level_has_effective_benefit = false,
      settings = {maximum_level = {name = "max", default = 3, raw_direct = 3, effective = 3, source = "direct", changed = false, changed_from_default = false, restart_required = true}, enabled = {name = "enabled", default = true, raw_direct = true, effective = true, source = "direct", changed = false, changed_from_default = false, restart_required = true}}}}
  }
  local crossed = core.detail(catalogue, technology_name, cross_bound)
  check(crossed and crossed.enrichment == nil, "cross-bound fake provider detail was accepted")
  local cap_on_generic = {
    schema = 2, kind = "portable-research-enrichment",
    caps = {[technology_name] = 3}, families = {[technology_name] = "research_material_tin"},
    details = {[technology_name] = {schema = 1, family = "research_material_tin", action = "emit"}}
  }
  local generic = core.detail(catalogue, technology_name, cap_on_generic)
  check(generic and generic.enrichment == nil, "cap-bound generic provider detail was accepted")
  local family_without_detail = {
    schema = 2, kind = "portable-research-enrichment", caps = {},
    families = {[technology_name] = "research_material_tin"}, details = {}
  }
  local missing = core.detail(catalogue, technology_name, family_without_detail)
  check(missing and missing.enrichment == nil, "family without provider detail was accepted")

  local valid = valid_synthetic_enrichment()
  local accepted = core.detail(catalogue, technology_name, valid)
  check(accepted and accepted.enrichment, "independent valid schema-2 control was rejected")
  local function rejects(value, message)
    local observed = core.detail(catalogue, technology_name, value)
    check(observed and observed.enrichment == nil, message)
  end

  local fractional = deep_copy(valid)
  fractional.caps[technology_name] = 3.5
  fractional.details[technology_name].effective_cap = 3.5
  rejects(fractional, "fractional cap was accepted")

  local wrong_name = deep_copy(valid)
  wrong_name.details[technology_name].settings.maximum_level.name = "ips-max-level-unrelated"
  rejects(wrong_name, "unrelated maximum-level setting was accepted")

  local wrong_type = deep_copy(valid)
  local wrong_enabled = wrong_type.details[technology_name].settings.enabled
  wrong_enabled.default = 1
  wrong_enabled.raw_direct = 1
  wrong_enabled.effective = 1
  rejects(wrong_type, "non-boolean enabled setting was accepted")

  local wrong_changed = deep_copy(valid)
  wrong_changed.details[technology_name].settings.maximum_level.changed_from_default = false
  rejects(wrong_changed, "false changed-from-default setting fact was accepted")

  local post_cap = deep_copy(valid)
  post_cap.details[technology_name].current_level = 4
  rejects(post_cap, "post-cap benefit=true detail was accepted")

  local nonfinite_level = deep_copy(valid)
  nonfinite_level.details[technology_name].current_level = math.huge
  nonfinite_level.details[technology_name].recipe_benefits[1].next_level_has_effective_benefit = false
  nonfinite_level.details[technology_name].next_level_has_effective_benefit = false
  rejects(nonfinite_level, "non-finite current level was accepted")

  local saturated = deep_copy(valid)
  saturated.details[technology_name].recipe_benefits[1].current_productivity_bonus = 1
  rejects(saturated, "saturated recipe benefit=true detail was accepted")

  local sparse_policy = provider.policy_caps_for_test({
    schema = 2,
    kind = "MIRMaximumLevelPolicyV2",
    bindings = {
      [1] = {
        technology = technology_name,
        selected = 3,
        setting = "ips-max-level-research_material_tin"
      },
      [3] = {
        technology = technology_name,
        selected = 4,
        setting = "ips-max-level-research_material_tin"
      }
    }
  })
  check(next(sparse_policy) == nil, "sparse policy binding array was accepted")
end

local function assert_duplicate_public_row_negative(force)
  local enrichment = provider.snapshot(force)
  check(enrichment.families[duplicate_name] == nil and enrichment.details[duplicate_name] == nil
    and enrichment.caps[duplicate_name] == nil, "duplicate public technology rows were rendered")
  for _, name in ipairs({wrong_schema_name, extra_field_name}) do
    check(enrichment.families[name] == nil and enrichment.details[name] == nil
      and enrichment.caps[name] == nil, "malformed public row was rendered " .. name)
  end
end

local function assert_non_recipe_regression(force)
  local catalogue, enrichment = catalogue_adapter.snapshot(force), provider.snapshot(force)
  local detail = core.detail(catalogue, non_recipe_name, enrichment)
  check(detail and detail.enrichment and detail.enrichment.family == "browser_non_recipe_regression"
    and detail.enrichment.action == "emit", "non-recipe family/action enrichment regressed")
  check(detail.enrichment.next_level_has_effective_benefit == nil and detail.enrichment.recipe_benefits == nil,
    "non-recipe row fabricated a recipe-benefit claim")
end

local function configure_level_three(force)
  force.research_all_technologies()
  local technology = force.technologies[technology_name]
  check(technology, "Tin technology is absent from player force")
  technology.level = 3
  force.research_queue = {technology}
  check(force.current_research and force.current_research.name == technology_name, "could not establish level-three current Tin research")
  force.research_progress = 0.42
  return technology
end

local function assert_level_negatives()
  local cap_force = game.create_force("mir-browser-cap-negative")
  cap_force.enable_all_prototypes()
  local technology = cap_force.technologies[technology_name]
  check(technology, "cap-negative force has no Tin technology")
  technology.level = 4
  local _, _, post_cap = detail_for(cap_force)
  check(post_cap.enrichment.next_level_has_effective_benefit == false, "post-cap level four was presented as beneficial")
  check(post_cap.enrichment.recipe_benefits[1].next_level_has_effective_benefit == false,
    "post-cap recipe benefit was presented as beneficial")
  check(provider.next_level_has_effective_benefit({enabled = true, researched = false, level = 3}, 3, {
    {effect_change = 0.02, current_productivity_bonus = 1, maximum_productivity = 1}
  }) == false, "saturated recipe benefit control was accepted")
end

local function assert_detail(detail)
  local value = detail.enrichment
  check(value.schema == 1, "Tin detail schema differs")
  check(value.owner.technology_id == technology_name and value.owner.stream_id == "research_material_tin"
    and value.owner.action == "emit" and value.owner.reason == "recipe_productivity", "Tin owner/action facts differ")
  check(#value.owner.affected_recipe_ids == 1 and value.owner.affected_recipe_ids[1] == recipe_name, "Tin affected recipe differs")
  check(value.compiler_disposition.inclusion == "included"
    and value.compiler_disposition.route_exclusions.state == "no-additional-route-exclusions-published-for-current-row"
    and #value.compiler_disposition.route_exclusions.recipe_ids == 0, "Tin row-local exclusion availability differs")
  check(value.final_science.rationale == "final-technology-prototype-cross-bound-to-public-generation-plan-row"
    and #value.final_science.ingredients == 1 and value.final_science.ingredients[1].name == "automation-science-pack"
    and value.final_science.ingredients[1].amount == 1, "Tin final science differs")
  check(value.effective_cap == 3 and value.current_level == 3 and value.next_level_has_effective_benefit == true, "level-three benefit facts differ")
  local benefit = value.recipe_benefits[1]
  check(benefit and benefit.recipe_id == recipe_name and benefit.effect_change == 0.02
    and type(benefit.current_productivity_bonus) == "number" and type(benefit.maximum_productivity) == "number"
    and benefit.current_productivity_bonus < benefit.maximum_productivity
    and benefit.next_level_has_effective_benefit == true, "Tin recipe productivity-cap facts differ")
  local maximum, enabled = value.settings.maximum_level, value.settings.enabled
  check(maximum.name == "ips-max-level-research_material_tin" and maximum.default == 2
    and maximum.raw_direct == 2 and maximum.effective == 3 and maximum.source == "mirset1"
    and maximum.changed == true and maximum.changed_from_default == true
    and maximum.restart_required == true, "Tin maximum setting comparison differs")
  check(enabled.name == "ips-enable-research_material_tin" and enabled.default == true
    and enabled.raw_direct == true and enabled.effective == true and enabled.source == "mirset1"
    and enabled.changed == false and enabled.changed_from_default == false
    and enabled.restart_required == true, "Tin enable setting comparison differs")
end

local function assert_native_ui(player, force)
  local before = force_snapshot(force)
  check(remote.call("more-infinite-research-browser", "open", player.index, {
    tab = "research", selected = technology_name, search = technology_name
  }), "native browser did not open")
  check(before == force_snapshot(force), "opening browser explanation mutated force research state")
  local frame = player.gui.screen.mir_research_browser
  check(frame and frame.valid, "native browser frame is absent")
  local facts = {}
  capture_facts(frame, facts)
  check(facts.affected_recipes == "Affected recipes: bob-tin-plate", "affected-recipe GUI caption differs")
  check(contains(facts.compiler_disposition, "Compiler disposition: included | action=emit | reason=recipe_productivity"), "compiler GUI caption differs")
  check(contains(facts.route_exclusions, "no-additional-route-exclusions-published-for-current-row"), "route-exclusion GUI caption differs")
  check(contains(facts.science, "Final science: automation-science-pack x1"), "science GUI caption differs")
  check(contains(facts.next_level, "Next level has effective benefit: true | current-level=3 | effective-cap=3"), "benefit GUI caption differs")
  check(contains(facts.recipe_benefits, "bob-tin-plate current-productivity="), "recipe-cap GUI caption differs")
  check(contains(facts.maximum_setting, "ips-max-level-research_material_tin | default=2 | raw-direct=2 | effective=3 | source=mirset1 | changed=true | changed-from-default=true | restart-required=true"), "maximum-setting GUI caption differs")
  check(contains(facts.enabled_setting, "ips-enable-research_material_tin | default=true | raw-direct=true | effective=true | source=mirset1 | changed=false | changed-from-default=false | restart-required=true"), "enable-setting GUI caption differs")
  check(facts.startup_restart == "Startup settings require restart; this browser does not mutate startup settings.", "restart GUI caption differs")
  return facts
end

script.on_init(function()
  for _, name in ipairs({"boblibrary", "bobores", "bobplates", "more-infinite-research"}) do
    if not script.active_mods[name] then fail("locked Bob-only runtime closure is missing " .. name) end
  end
  for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do
    if script.active_mods[name] then fail("Bob-only browser fixture loaded " .. name) end
  end
  storage.mir_bob_tin_browser_explanation = {complete = false}
  configure_level_three(game.forces.player)
end)

script.on_nth_tick(1, function()
  local state = storage.mir_bob_tin_browser_explanation
  if not state then return end
  if state.complete then return end
  local force = game.forces.player
  local catalogue, _, detail = detail_for(force)
  assert_fake_and_limit_negatives(catalogue)
  assert_non_recipe_regression(force)
  assert_duplicate_public_row_negative(force)
  assert_detail(detail)
  assert_level_negatives()
  local player = game.players[1]
  local facts = player and assert_native_ui(player, force) or {}
  helpers.write_file("bob-tin-browser-explanation.json", helpers.table_to_json({
    status = "passed",
    scope = "F210-exact-locked-Bob-only-browser-explanation",
    execution_surface = player and "native-player-gui" or "headless-dto",
    detail = detail,
    ui_facts = facts,
    native_players = player and 1 or 0
  }), false)
  state.complete = true
  game.auto_save("mir-bob-tin-browser-explanation")
end)
