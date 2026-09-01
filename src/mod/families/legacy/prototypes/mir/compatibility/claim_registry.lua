local M = {}

M.schema = 1

M.authority = {
  governance = ".mir/compatibility.yml",
  fixture_claims = "fixtures/compat-matrix/claims.json"
}

M.claims = {
  {
    id = "air-scrubbing",
    mod = "atan-air-scrubbing",
    doc = "docs/compatibility/targets/atan-air-scrubbing.md",
    claim_level = "full-family-support",
    public_claim = "clean-filter crafting productivity only",
    capabilities = {
      ["recipe-productivity"] = "generated",
      ["loop-risk"] = "diagnostic-only"
    },
    streams = {
      "mir-prod-air-scrubbing-clean-filter"
    },
    fixtures = {
      "fixtures/air-scrubbing",
      "fixtures/assert-air-scrubbing-clean-filter"
    },
    generated = {
      "atan-pollution-filter",
      "atan-spore-filter"
    },
    diagnostic_only = {
      "scrubbing-environmental",
      "cleaning-recovery"
    }
  },
  {
    id = "atan-ash",
    mod = "atan-ash",
    doc = "docs/compatibility/targets/atan-ash.md",
    claim_level = "full-family-support",
    public_claim = "ash separation productivity only",
    capabilities = {
      ["recipe-productivity"] = "generated",
      ["tile-surface"] = "diagnostic-only",
      ["resource-recovery"] = "diagnostic-only",
      ["loader-schema-repair"] = "exact-version recipe category and product probability schema normalization"
    },
    streams = {
      "mir-prod-atan-ash-separation"
    },
    fixtures = {
      "fixtures/atan-ash",
      "fixtures/assert-atan-ash-separation"
    },
    generated = {
      "atan-ash-seperation"
    },
    diagnostic_only = {
      "ash-sinks",
      "tile-surface",
      "resource-recovery"
    }
  },
  {
    id = "atan-nuclear-science",
    mod = "atan-nuclear-science",
    doc = "docs/compatibility/targets/atan-nuclear-science.md",
    claim_level = "partial-support",
    public_claim = "science-pack recipe productivity only",
    capabilities = {
      ["science-pack-integration"] = "generated-through-existing-stream",
      ["lab-compatibility"] = "validated",
      ["loader-schema-repair"] = "exact-version recipe category schema normalization"
    },
    generated_through_existing_stream = "research_science_pack_productivity",
    fixtures = {
      "fixtures/atan-nuclear-science",
      "fixtures/assert-atan-nuclear-science-productivity"
    },
    diagnostic_only = {
      "atom-forge-crafting"
    }
  },
  {
    id = "aai-loaders",
    mod = "aai-loaders",
    doc = "docs/compatibility/targets/aai-loaders.md",
    claim_level = "partial-support",
    public_claim = "loader crafting productivity only",
    capabilities = {
      ["logistics-loader-manufacturing"] = "generated-through-existing-stream",
      ["native-belt-stack-size"] = "observed"
    },
    generated_through_existing_stream = "research_belts",
    fixtures = {
      "fixtures/aai-loaders",
      "fixtures/assert-aai-loader-belt-productivity"
    },
    diagnostic_only = {
      "loader-throughput",
      "loader-modes",
      "compatibility-hooks"
    }
  },
  {
    id = "big-mining-drill",
    mod = "big-mining-drill",
    doc = "docs/compatibility/targets/big-mining-drill.md",
    claim_level = "partial-support",
    public_claim = "mining drill recipe productivity only",
    capabilities = {
      ["mining-drill-manufacturing"] = "generated-through-existing-stream",
      ["native-mining-yield-productivity"] = "observed"
    },
    generated_through_existing_stream = "research_mining_drill",
    fixtures = {
      "fixtures/big-mining-drill",
      "fixtures/assert-big-mining-drill-productivity"
    },
    diagnostic_only = {
      "native-mining-yield-productivity"
    }
  },
  {
    id = "modules-t4",
    mod = "modules-t4",
    doc = "docs/compatibility/targets/modules-t4.md",
    claim_level = "partial-support",
    public_claim = "module recipe productivity by final prototype tier",
    capabilities = {
      ["recipe-productivity"] = "generated-through-existing-stream",
      ["dynamic-module-effect-research"] = "not-owned"
    },
    generated_through_existing_stream = "research_modules",
    fixtures = {
      "fixtures/assert-prototype-limits"
    },
    named_load_checks = {
      "modules-t4_2.2.2 source archive on Factorio 2.1.9"
    },
    diagnostic_only = {
      "dynamic-module-effect-research",
      "module-effect-mutation"
    }
  },
  {
    id = "finite-prod-techs",
    mod = "finite_prod_techs",
    doc = "docs/compatibility/targets/finite-prod-techs.md",
    claim_level = "cooperates",
    public_claim = "load-after finite productivity cap post-processing",
    capabilities = {
      ["finite-productivity-post-processing"] = "external-owner",
      ["finite-level-formula"] = "not-owned"
    },
    named_load_checks = {
      "finite_prod_techs_0.1.1 source archive on Factorio 2.1.9"
    },
    diagnostic_only = {
      "finite-level-formula-ownership"
    }
  },
  {
    id = "fluid-must-flow",
    mod = "FluidMustFlow",
    doc = "docs/compatibility/targets/fluid-must-flow.md",
    claim_level = "diagnostic-only",
    public_claim = "pipeline coexistence only",
    capabilities = {
      ["pipeline-extent"] = "coexistence-check",
      ["recipe-productivity"] = "diagnostic-only"
    },
    named_load_checks = {
      "release-targeted local repair check"
    },
    diagnostic_only = {
      "duct-behavior",
      "fluid-logistics"
    }
  },
  {
    id = "robot-attrition",
    mod = "robot_attrition",
    doc = "docs/compatibility/targets/robot-attrition.md",
    claim_level = "diagnostic-only",
    public_claim = "runtime balance coexistence only",
    capabilities = {
      ["rule-surface"] = "coexistence-check",
      ["runtime-productivity"] = "not-owned"
    },
    named_load_checks = {
      "release-targeted local repair check"
    },
    diagnostic_only = {
      "robot-crash-behavior",
      "attrition-behavior",
      "recovery-behavior"
    }
  },
  {
    id = "jetpack",
    mod = "jetpack",
    doc = "docs/compatibility/targets/jetpack.md",
    claim_level = "diagnostic-only",
    public_claim = "equipment content coexistence only",
    capabilities = {
      ["equipment-content"] = "coexistence-check",
      ["runtime-movement"] = "not-owned"
    },
    named_load_checks = {
      "release-targeted local repair check"
    },
    diagnostic_only = {
      "runtime-movement",
      "fuel-behavior",
      "equipment-behavior"
    }
  },
  {
    id = "equipment-gantry",
    mod = "equipment-gantry",
    doc = "docs/compatibility/targets/equipment-gantry.md",
    claim_level = "diagnostic-only",
    public_claim = "equipment-grid automation coexistence only",
    capabilities = {
      ["equipment-grid-automation"] = "coexistence-check",
      ["recipe-productivity"] = "diagnostic-only"
    },
    named_load_checks = {
      "release-targeted local repair check"
    },
    diagnostic_only = {
      "gantry-insertion",
      "gantry-removal",
      "item-grid-processing"
    }
  },
  {
    id = "aai-containers",
    mod = "aai-containers",
    doc = "docs/compatibility/targets/aai-containers.md",
    claim_level = "diagnostic-only",
    public_claim = "storage content coexistence only",
    capabilities = {
      ["storage-content"] = "coexistence-check",
      ["recipe-productivity"] = "diagnostic-only"
    },
    named_load_checks = {
      "release-targeted local repair check"
    },
    diagnostic_only = {
      "warehouse-productivity",
      "container-productivity"
    }
  },
  {
    id = "aai-industry",
    mod = "aai-industry",
    doc = "docs/compatibility/targets/aai-industry.md",
    claim_level = "observed",
    public_claim = "mini-overhaul tuning profile",
    capabilities = {
      ["recipe-classification"] = "coexistence-check",
      ["science-lab"] = "coexistence-check",
      ["machine-facts"] = "coexistence-check"
    },
    named_load_checks = {
      "release-targeted local repair check"
    },
    diagnostic_only = {
      "broad-aai-suite-support"
    }
  }
}

M.by_mod = {}
M.by_id = {}

for _, claim in ipairs(M.claims) do
  M.by_id[claim.id] = claim
  M.by_mod[claim.mod] = claim
end

function M.get_by_id(id)
  return M.by_id[id]
end

function M.get_by_mod(mod)
  return M.by_mod[mod]
end

function M.all()
  return M.claims
end

return M
