-- Generated from .mir/technology-effect-targets.json. Do not edit by hand.
return {
  contracts = {
    ["ammo-damage"] = {
      identity_fields = {
        "type",
        "ammo_category"
      },
      targets = {
        {
          field = "ammo_category",
          prototype_type = "ammo-category",
          required = true
        }
      }
    },
    ["change-recipe-productivity"] = {
      identity_fields = {
        "type",
        "recipe"
      },
      targets = {
        {
          field = "recipe",
          prototype_type = "recipe",
          required = true
        }
      }
    },
    ["give-item"] = {
      identity_fields = {
        "type",
        "item",
        "quality"
      },
      targets = {
        {
          field = "item",
          required = true,
          resolver = "item"
        },
        {
          default = "normal",
          field = "quality",
          prototype_type = "quality",
          required = false
        }
      }
    },
    ["gun-speed"] = {
      identity_fields = {
        "type",
        "ammo_category"
      },
      targets = {
        {
          field = "ammo_category",
          prototype_type = "ammo-category",
          required = true
        }
      }
    },
    ["turret-attack"] = {
      identity_fields = {
        "type",
        "turret_id"
      },
      targets = {
        {
          field = "turret_id",
          required = true,
          resolver = "entity"
        }
      }
    },
    ["unlock-quality"] = {
      identity_fields = {
        "type",
        "quality"
      },
      targets = {
        {
          field = "quality",
          prototype_type = "quality",
          required = true
        }
      }
    },
    ["unlock-recipe"] = {
      identity_fields = {
        "type",
        "recipe"
      },
      targets = {
        {
          field = "recipe",
          prototype_type = "recipe",
          required = true
        }
      }
    },
    ["unlock-space-location"] = {
      identity_fields = {
        "type",
        "space_location"
      },
      targets = {
        {
          field = "space_location",
          required = true,
          resolver = "space-location"
        }
      }
    }
  },
  factorio_api_version = "2.1.11",
  factorio_target = "2.1",
  schema = 1
}
