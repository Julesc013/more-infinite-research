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
end
