local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")

data:extend({
    {
        type = "simple-entity",
        name = "rift-rail-collider",

        flags = {
            "hide-alt-info",
            "not-repairable",
            "not-blueprintable",
            "not-deconstructable",
            "not-on-map"
        },

        hidden = true,
        selectable_in_game = false,

        max_health = 1,
        picture = sprites.blank_sprite,

        collision_box = util.create_centered_box(2, 2),
        collision_mask = {
            layers = {
                ["train"] = true
            }
        },
    },
})
