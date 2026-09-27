-- Controlled presentation boundary checks, included in the existing browser
-- campaign. No extra engine launch and no product remote mutation interface.
local function check_omissions(check)
  local function skip(stream, technology)
    return {
      schema = 1, stream_id = stream, technology_id = technology,
      action = "skip", reason = "disabled", effect_count = 0,
      effect_identities = {}, affected_recipe_ids = {},
      disposition = {schema = 1, inclusion = "excluded", action = "skip", reason = "disabled",
        route_exclusions = {state = "no-additional-route-exclusions-published-for-current-row", recipe_ids = {}}},
      decision_fingerprint = "fixture-decision"
    }
  end
  local function set_artifact(rows)
    local artifact = {schema = 1, kind = "mir-generation-plan-public", rows = rows}
    artifact.public_fingerprint = browser_omission_fingerprint.of(artifact)
    browser_omission_prototypes.mod_data["more-infinite-research-generation-plan"] = {data = artifact}
    browser_omission_provider.invalidate_omissions()
    return artifact
  end
  local force = {valid = true, technologies = {}}
  set_artifact({skip("research_alpha", "absent-alpha"), skip("research_beta")})
  local result = browser_omission_provider.omissions(force)
  check(result and result.schema == 1 and result.kind == "portable-research-omissions"
    and #result.rows == 2 and result.rows[1].status == "not-added", "verified skips form a separate absent catalogue")
  result.rows[1].reason = "invented-removal"
  check(browser_omission_provider.omissions(force).rows[1].reason == "disabled", "omission DTO copies cannot mutate cached evidence")
  force.technologies["absent-alpha"] = {valid = true, enabled = false, researched = false}
  check(#browser_omission_provider.omissions(force).rows == 1, "existing disabled research is not reported absent")
  check(#browser_omission_provider.omissions({valid = true, technologies = {}}).rows == 2, "absent status is force specific")
  local artifact = set_artifact({skip("research_alpha")})
  artifact.rows[1].reason = "removed"
  check(browser_omission_provider.omissions(force) == nil, "unsealed omission change fails closed")
  set_artifact({skip("research_alpha"), skip("research_alpha")})
  check(browser_omission_provider.omissions(force) == nil, "ambiguous duplicate omission fails closed")
  local wrong = skip("research_alpha")
  wrong.disposition.inclusion = "included"
  set_artifact({wrong})
  check(browser_omission_provider.omissions(force) == nil, "opposing inclusion and skip do not become absence proof")
  wrong = skip("research_alpha")
  wrong.technology_id = ""
  set_artifact({wrong})
  check(browser_omission_provider.omissions(force) == nil, "empty technology identity is not an absent-identity sentinel")
  set_artifact({skip("research_gamma")})
  check(browser_omission_provider.omissions(force).rows[1].stream_id == "research_gamma", "configuration invalidation adopts current omission facts")
  check(browser_omission_provider.omissions({valid = false}) == nil, "invalid force cannot publish omission facts")

  local function admitted(action, stream, technology)
    return {
      schema = 1, stream_id = stream, technology_id = technology,
      action = action, reason = "fixture", effect_count = 0,
      effect_identities = {}, affected_recipe_ids = {},
      disposition = {schema = 1, inclusion = "included", action = action, reason = "fixture",
        route_exclusions = {state = "no-additional-route-exclusions-published-for-current-row", recipe_ids = {}}},
      decision_fingerprint = "fixture-" .. action
    }
  end
  local function empty_enrichment(value)
    return value and not next(value.families or {}) and not next(value.details or {}) and not next(value.caps or {})
  end
  local absent_force = {valid = true, technologies = {}}
  set_artifact({skip("research_skip_absent", "skip-absent")})
  check(empty_enrichment(browser_omission_provider.snapshot(absent_force)),
    "absent skip cannot create a managed provider family")
  local disabled_foreign_force = {valid = true, technologies = {
    ["skip-live"] = {valid = true, enabled = false, researched = false}
  }}
  set_artifact({skip("research_skip_live", "skip-live")})
  check(empty_enrichment(browser_omission_provider.snapshot(disabled_foreign_force)),
    "disabled foreign technology cannot turn a skip into managed research")
  set_artifact({admitted("emit", "research_emit_absent", "emit-absent")})
  check(empty_enrichment(browser_omission_provider.snapshot(absent_force)),
    "absent emitted technology cannot create managed provider ownership")
  local live_force = {valid = true, technologies = {
    ["emit-live"] = {valid = true},
    ["adopt-live"] = {valid = true}
  }}
  set_artifact({
    admitted("emit", "research_emit_live", "emit-live"),
    admitted("adopt", "research_adopt_live", "adopt-live")
  })
  local live_enrichment = browser_omission_provider.snapshot(live_force)
  check(live_enrichment.families["emit-live"] == "research_emit_live"
    and live_enrichment.details["emit-live"].action == "emit"
    and live_enrichment.families["adopt-live"] == "research_adopt_live"
    and live_enrichment.details["adopt-live"].action == "adopt",
    "live admitted empty-effect rows retain managed provider identities")
  local unsealed = set_artifact({
    admitted("emit", "research_emit_unsealed", "emit-live"),
    admitted("adopt", "research_adopt_unsealed", "adopt-live")
  })
  unsealed.rows[1].stream_id = "research_emit_unsealed_changed"
  check(empty_enrichment(browser_omission_provider.snapshot(live_force)),
    "unsealed live emit and adopt rows cannot create managed provider enrichment")
  local original_limit = browser_omission_provider.catalogue_limit
  set_artifact({
    admitted("emit", "research_bounded_emit", "emit-live"),
    admitted("adopt", "research_bounded_adopt", "adopt-live"),
    admitted("emit", "research_bounded_absent", "emit-absent")
  })
  check(browser_omission_provider.snapshot(live_force).families["emit-live"] == "research_bounded_emit",
    "sealed catalogue below the normal bound admits a live candidate")
  browser_omission_provider.catalogue_limit = 2
  local bounded_enrichment = browser_omission_provider.snapshot(live_force)
  browser_omission_provider.catalogue_limit = original_limit
  check(empty_enrichment(bounded_enrichment),
    "over-limit sealed rows reject before a live candidate can create enrichment")
  set_artifact({
    admitted("emit", "research_duplicate_emit", "duplicate-live"),
    skip("research_duplicate_skip", "duplicate-live")
  })
  check(empty_enrichment(browser_omission_provider.snapshot({valid = true, technologies = {
    ["duplicate-live"] = {valid = true}
  }})), "skip shadow duplicate still fails closed for a managed provider identity")
end
