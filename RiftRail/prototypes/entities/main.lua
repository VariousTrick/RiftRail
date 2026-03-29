local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")

data:extend({
    {
        type = "simple-entity-with-owner",
        name = "rift-rail-entity",
        icon = "__RiftRail__/graphics/entity.png",
        icon_size = 64,

        flags = {
            "placeable-neutral",
            "player-creation",
            "placeable-off-grid",
            "not-rotatable"
        },

        placeable_by = { { item = "rift-rail-placer", count = 1 } },

        minable = { mining_time = 1, result = "rift-rail-placer" },
        max_health = 100000,

        collision_mask = {
            layers = {
                ["water_tile"] = true,
                ["item"] = true,
                ["player"] = true,
            },
        },

        collision_box = util.create_centered_box(3.8, 11.8),
        selection_box = util.create_centered_box(4, 12),
        build_grid_size = 2,

        picture = sprites.main_picture,

        render_layer = "train-stop-top",
    },
})
