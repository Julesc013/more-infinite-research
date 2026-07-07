return {
  schema = 1,

  rules = {
    hidden_means_unavailable_not_deleted = true,
    do_not_force_hidden_values_by_default = true,
    setting_ids_are_stable = true,
    data_stage_must_validate_targets = true
  },

  global = {
    {
      key = "ips-require-space-gate",
      ui_visibility = { mode = "always" }
    },
    {
      key = "mir-science-pack-ingredient-policy",
      ui_visibility = { mode = "always" }
    },
    {
      key = "mir-lab-incompatibility-policy",
      ui_visibility = { mode = "always" }
    },
    {
      key = "mir-prefer-this-mod-for-competing-techs",
      ui_visibility = { mode = "always" }
    },
    {
      key = "mir-adjust-vanilla-weapon-speed-techs",
      ui_visibility = { mode = "always" }
    },
    {
      key = "mir-use-installed-space-age-icons",
      ui_visibility = { mode = "always" }
    },
    {
      key = "mir-pipeline-extent-multiplier",
      ui_visibility = { mode = "always" }
    },
    {
      key = "mir-debug-generation-report",
      ui_visibility = { mode = "always" }
    },
    {
      key = "mir-debug-recipe-matches",
      ui_visibility = { mode = "always" }
    },
    {
      key = "mir-debug-scripted-effects",
      ui_visibility = { mode = "always" }
    }
  },

  stream_setting_group = {
    setting_names = {
      enable = "ips-enable-%s",
      base_cost = "ips-cost-base-%s",
      growth = "ips-cost-growth-%s",
      max_level = "ips-max-level-%s",
      research_time = "ips-research-time-%s"
    }
  }
}
