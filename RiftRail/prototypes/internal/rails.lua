local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")

local source =
    data.raw["legacy-straight-rail"]["legacy-straight-rail"]
    or data.raw["legacy-straight-rail"]["straight-rail"]

local rail = {}

for k, v in pairs(source) do
    if k ~= "pictures" then
        rail[k] = table.deepcopy(v)
    end
end

rail.type = "legacy-straight-rail"
rail.name = "rift-rail-internal-rail"
rail.minable = nil
rail.flags = {
    "hide-alt-info",
    "not-repairable",
    "not-blueprintable",
    "not-deconstructable",
    "not-on-map"
}

rail.hidden = true
rail.selectable_in_game = false

rail.pictures = {
    render_layers = {
        stone_path = "rail-stone-path",
        ties = "rail-ties",
        backplates = "rail-backplates",
        metals = "rail-metals",
    },

    north = {
        metals = {
            filename = "__RiftRail__/graphics/rail_v.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
        },
        backplates = sprites.blank_sprite,
        ties = sprites.blank_sprite,
        stone_path = sprites.blank_sprite,
    },

    south = {
        metals = {
            filename = "__RiftRail__/graphics/rail_v.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
        },
        backplates = sprites.blank_sprite,
        ties = sprites.blank_sprite,
        stone_path = sprites.blank_sprite,
    },

    east = {
        metals = {
            filename = "__RiftRail__/graphics/rail_h.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
        },
        backplates = sprites.blank_sprite,
        ties = sprites.blank_sprite,
        stone_path = sprites.blank_sprite,
    },

    west = {
        metals = {
            filename = "__RiftRail__/graphics/rail_h.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
        },
        backplates = sprites.blank_sprite,
        ties = sprites.blank_sprite,
        stone_path = sprites.blank_sprite,
    },

    northeast = sprites.blank_sprite,
    southeast = sprites.blank_sprite,
    southwest = sprites.blank_sprite,
    northwest = sprites.blank_sprite,

    rail_endings = sprites.blank_sheet,
    ties = sprites.blank_sheet,
    stone_path = sprites.blank_sheet,
    stone_path_background = sprites.blank_sheet,

    segment_visualisation_middle = sprites.blank_sprite,
    segment_visualisation_ending_front = sprites.blank_sprite,
    segment_visualisation_ending_back = sprites.blank_sprite,
    segment_visualisation_continuing_front = sprites.blank_sprite,
    segment_visualisation_continuing_back = sprites.blank_sprite,
}

data:extend({ rail })
