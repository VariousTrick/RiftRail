local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")

data:extend({
    {
        type = "lamp",
        name = "rift-rail-lamp",
        icon = "__base__/graphics/icons/small-lamp.png",
        icon_size = 64,

        flags = {
            "hide-alt-info",
            "not-blueprintable",
            "not-deconstructable",
            "not-on-map"
        },

        hidden = true,
        selectable_in_game = false,

        collision_mask = { layers = {} },
        collision_box = util.create_centered_box(0, 0),
        selection_box = util.create_centered_box(0, 0),

        energy_source = { type = "void" },
        energy_usage_per_tick = "1W",

        picture_off = sprites.blank_sprite,
        picture_on = sprites.blank_sprite,

        light = {
            intensity = 0.9,
            size = 40,
            color = { r = 0.9, g = 0.9, b = 1.0 }
        },
    },
})
