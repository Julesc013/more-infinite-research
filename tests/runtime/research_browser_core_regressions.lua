-- Pure portable-core regressions. The native browser harness loads this file
-- inside its controlled fixture and supplies browser_core plus its assertion
-- function. Keep it free of Factorio runtime objects so these failures remain
-- cheap and precise when the UI host changes independently.
return function(browser_core, check)
  local technology = "core-regression-productivity"
  local family = "core-regression"
  local catalogue = {
    schema = 1,
    rows = {{
      key = technology,
      available = true,
      researched = false,
      queued = false,
      infinite = true,
      native_order = "core-regression",
      progression = 1
    }}
  }

  local function maximum_setting(default, raw_direct, effective, source)
    return {
      name = "ips-max-level-" .. family,
      default = default,
      raw_direct = raw_direct,
      effective = effective,
      source = source,
      changed = raw_direct ~= effective,
      changed_from_default = default ~= effective,
      restart_required = true
    }
  end

  local function recipe_benefits(count)
    local ids, benefits = {}, {}
    for index = 1, count do
      local recipe_id = string.format("core-regression-recipe-%03d", index)
      ids[index] = recipe_id
      benefits[index] = {
        recipe_id = recipe_id,
        effect_change = 0.02,
        current_productivity_bonus = 0,
        maximum_productivity = 1,
        next_level_has_effective_benefit = true
      }
    end
    return ids, benefits
  end

  local function envelope(default, raw_direct, effective, source, recipe_count)
    local ids, benefits = recipe_benefits(recipe_count or 1)
    return {
      schema = 2,
      kind = "portable-research-enrichment",
      caps = {[technology] = effective},
      families = {[technology] = family},
      details = {
        [technology] = {
          schema = 1,
          family = family,
          action = "emit",
          owner = {
            technology_id = technology,
            stream_id = family,
            action = "emit",
            reason = "core-regression",
            affected_recipe_ids = ids
          },
          compiler_disposition = {
            inclusion = "included",
            action = "emit",
            reason = "core-regression",
            route_exclusions = {
              state = "no-additional-route-exclusions-published-for-current-row",
              recipe_ids = {}
            }
          },
          final_science = {
            rationale = "core-regression",
            ingredients = {{name = "automation-science-pack", amount = 1}}
          },
          effective_cap = effective,
          current_level = 1,
          recipe_benefits = benefits,
          next_level_eligible = true,
          next_level_has_effective_benefit = true,
          settings = {
            maximum_level = maximum_setting(default, raw_direct, effective, source),
            enabled = {
              name = "ips-enable-" .. family,
              default = true,
              raw_direct = true,
              effective = true,
              source = "direct",
              changed = false,
              changed_from_default = false,
              restart_required = true
            }
          }
        }
      }
    }
  end

  local imported = envelope(0, 0, 10, "mirset1")
  local imported_detail = browser_core.detail(catalogue, technology, imported)
  check(browser_core.normalize_enrichment(imported) ~= nil
      and imported_detail and imported_detail.technology.cap == 10
      and imported_detail.enrichment.settings.maximum_level.default == 0
      and imported_detail.enrichment.settings.maximum_level.raw_direct == 0,
    "zero default and raw maximum remain valid when a MIRSET1 override selects a finite cap")

  local direct = envelope(0, 10, 10, "direct")
  check(browser_core.normalize_enrichment(direct) ~= nil
      and browser_core.detail(catalogue, technology, direct).technology.cap == 10,
    "zero default remains valid when a direct setting selects a finite cap")

  local negative_default = envelope(-1, 10, 10, "direct")
  check(browser_core.normalize_enrichment(negative_default) == nil,
    "negative maximum defaults remain rejected")
  local fractional_direct = envelope(0, 1.5, 10, "direct")
  check(browser_core.normalize_enrichment(fractional_direct) == nil,
    "fractional maximum direct values remain rejected")
  local zero_effective = envelope(0, 0, 10, "mirset1")
  zero_effective.details[technology].settings.maximum_level.effective = 0
  zero_effective.details[technology].settings.maximum_level.changed = false
  zero_effective.details[technology].settings.maximum_level.changed_from_default = false
  check(browser_core.normalize_enrichment(zero_effective) == nil,
    "a finite detail still rejects an unbounded effective cap")

  local wide = envelope(0, 0, 10, "mirset1", 70)
  wide.details[technology].recipe_benefits[1].effect_change = 0.01
  wide.details[technology].recipe_benefits[1].current_productivity_bonus = 0.1
  wide.details[technology].recipe_benefits[1].maximum_productivity = 0.5
  wide.details[technology].recipe_benefits[70].effect_change = 0.05
  wide.details[technology].recipe_benefits[70].current_productivity_bonus = 0.2
  wide.details[technology].recipe_benefits[70].maximum_productivity = 2
  local wide_detail, wide_reason = browser_core.detail(catalogue, technology, wide)
  check(wide_detail and wide_reason == nil and wide_detail.enrichment
      and wide_detail.enrichment.recipe_benefit_count == 70
      and #wide_detail.enrichment.recipe_benefits == browser_core.detail_summary_recipe_limit
      and not wide_detail.enrichment.recipe_benefits_complete,
    "valid broad details return a bounded summary instead of enrichment-limit")
  local recipe_index = browser_core.detail_recipe_index(catalogue, technology, wide)
  check(recipe_index and #recipe_index.ids == 70
      and recipe_index.ids[1] == "core-regression-recipe-001"
      and recipe_index.ids[70] == "core-regression-recipe-070"
      and recipe_index.summary.count == 70 and recipe_index.summary.effective_recipe_count == 70
      and recipe_index.summary.effect_change_min == 0.01 and recipe_index.summary.effect_change_max == 0.05
      and recipe_index.summary.current_productivity_bonus_min == 0
      and recipe_index.summary.current_productivity_bonus_max == 0.2
      and recipe_index.summary.maximum_productivity_min == 0.5
      and recipe_index.summary.maximum_productivity_max == 2,
    "a selected detail exposes all validated recipe IDs with an aggregate productivity summary")
  recipe_index.ids[1] = "poisoned"
  check(browser_core.detail_recipe_index(catalogue, technology, wide).ids[1] == "core-regression-recipe-001",
    "recipe indexes return detached lightweight IDs")
  local first_window = browser_core.detail_recipe_benefits(catalogue, technology, wide)
  local final_window = browser_core.detail_recipe_benefits(catalogue, technology, wide, first_window.next_offset, 64)
  check(first_window.count == 70 and #first_window.rows == 64 and not first_window.complete
      and first_window.next_offset == 65 and final_window and #final_window.rows == 6
      and final_window.complete and final_window.next_offset == nil,
    "validated broad recipe facts remain available through bounded collection access")
  first_window.rows[1].recipe_id = "poisoned"
  local copied_again = browser_core.detail_recipe_benefits(catalogue, technology, wide, 1, 1)
  check(copied_again.rows[1].recipe_id == "core-regression-recipe-001",
    "recipe collection access returns detached records")

  local query_catalogue = {schema = 1, rows = {}}
  for index = 1, 25 do
    query_catalogue.rows[index] = {
      key = string.format("core-query-%03d", index),
      available = true,
      researched = false,
      queued = false,
      infinite = false,
      native_order = "",
      progression = index
    }
  end
  local paged = browser_core.query(query_catalogue, {mode = 1, status = 1, page = 2, sort = "progression"})
  local all = browser_core.query_all(query_catalogue, {mode = 1, status = 1, sort = "progression"})
  check(paged.count == 25 and paged.pages == 2 and paged.page == 2 and #paged.rows == 5
      and paged.rows[1].key == "core-query-021"
      and all.count == 25 and #all.rows == 25 and all.rows[1].key == "core-query-001"
      and all.pages == nil and all.page_size == nil,
    "query_all exposes one sorted lightweight collection without changing legacy page semantics")
  all.rows[1].progression = 999
  check(browser_core.query_all(query_catalogue, {mode = 1, status = 1, sort = "progression"}).rows[1].progression == 1,
    "query_all rows cannot mutate the catalogue")
end
